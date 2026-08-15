#Requires -Version 5.1
<#
.SYNOPSIS
  DSH 左侧工作区「会话置顶」增强 - 一键安装脚本

.DESCRIPTION
  给 DeepSeek Harness 左侧工作区(workspace browser)的会话列表加入"置顶"功能:
  - 每条会话悬停时出现图钉按钮,或通过 ⋯ 菜单「置顶会话 / 取消置顶」
  - 被置顶的会话统一显示在列表顶部的「置顶」区块,按置顶时间倒序
  - 置顶状态保存在浏览器本地(localStorage),刷新/重启后依然保留

  原理:将 @deepseek-ai/dsh-client-ui-workspace 的客户端 bundle
  (lib/client.js) 替换为打了补丁的版本。脚本会自动:
  1. 定位 DSH 安装目录(也可用 -DshRoot 显式指定)
  2. 校验目标文件是否为受支持的原始版本(哈希或内容锚点)
  3. 备份原文件为 client.js.bak-dshpin
  4. 写入补丁版并回读校验

  !!! 请先完全退出 DSH(桌面版/Web 服务)再运行本脚本 !!!

.PARAMETER DshRoot
  可选。DSH 宿主安装根目录,即包含 node_modules 的 resources\host 目录。
  不指定时脚本会自动扫描常见安装位置与 %USERPROFILE%\.dsh 配置目录。

.PARAMETER Force
  可选。当目标文件的哈希与预期不一致、但内容锚点匹配(属于同一代码代次)时,
  仍继续安装(会先备份,可用 uninstall.ps1 还原)。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -DshRoot "D:\Tools\DeepSeek Harness\resources\host"
#>
[CmdletBinding()]
param(
    [string]$DshRoot = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Host.UI.RawUI.WindowTitle = "DSH 会话置顶 - 安装"

# ---------------------------------------------------------------------------
# 常量
# ---------------------------------------------------------------------------
$Rel = "node_modules\@deepseek-ai\dsh-client-ui-workspace\lib\client.js"
# 受支持的原始 client.js 的 SHA1(DeepSeek Harness 0.1.0-rc.5 桌面版构建)
$PristineSha1 = "3e60745ccd6515f194010c6d149bb4589728576c"
$SupportedNote = "DeepSeek Harness 0.1.0-rc.5 系列(2026-02 桌面构建)"
$PatchedFile = Join-Path $PSScriptRoot "patched\client.js"
$PatchedSha1 = ""  # 运行时计算

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "    !! $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "    XX $msg" -ForegroundColor Red }

function Get-Sha1($path) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $sha = [System.Security.Cryptography.SHA1]::Create()
    return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-", "").ToLower()
}


# ---------------------------------------------------------------------------
# 1. 定位目标
# ---------------------------------------------------------------------------
Write-Step "定位 DSH 安装目录 ..."
$candidates = New-Object 'System.Collections.Generic.List[string]'
if ($DshRoot) {
    $p = Join-Path $DshRoot $Rel
    if (Test-Path $p) { $candidates.Add($p) }
    else { Write-Fail "-DshRoot 下未找到 $Rel"; exit 1 }
}
$roots = @(
    (Join-Path $env:LOCALAPPDATA "Programs\DeepSeek Harness\resources\host"),
    (Join-Path ${env:ProgramFiles} "DeepSeek Harness\resources\host"),
    (Join-Path $env:USERPROFILE "AppData\Local\Programs\DeepSeek Harness\resources\host")
)
foreach ($r in $roots) {
    if ($r -and (Test-Path (Join-Path $r $Rel))) { $candidates.Add((Join-Path $r $Rel)) }
}
foreach ($drive in @("C:", "D:")) {
    Get-ChildItem (Join-Path $drive "Users") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Join-Path $_.FullName "AppData\Local\Programs\DeepSeek Harness\resources\host\$Rel"
        if (Test-Path $p) { $candidates.Add($p) }
    }
}
# DSH 配置目录里的包副本(与安装目录可能是同一文件/硬链接)
$profileCopy = Join-Path $env:USERPROFILE ".dsh\profiles\node_modules\@deepseek-ai\dsh-client-ui-workspace\lib\client.js"
if (Test-Path $profileCopy) { $candidates.Add($profileCopy) }

# 去重:按真实路径 + (文件大小, 最后写入时间) 判定同一文件
$seen = @{}
$targets = @()
foreach ($c in $candidates) {
    $full = [System.IO.Path]::GetFullPath($c)
    if (-not (Test-Path $full)) { continue }
    $item = Get-Item $full
    $key = "$($item.Length)|$($item.LastWriteTimeUtc.Ticks)"
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $targets += $full
}
if ($targets.Count -eq 0) {
    Write-Fail "未找到 DSH 安装。请用 -DshRoot 显式指定 resources\host 目录后重试。"
    exit 1
}
Write-Ok "找到 $($targets.Count) 处目标:"
foreach ($t in $targets) { Write-Ok "  $t" }

# ---------------------------------------------------------------------------
# 2. 校验补丁文件
# ---------------------------------------------------------------------------
if (-not (Test-Path $PatchedFile)) { Write-Fail "缺少补丁文件: $PatchedFile"; exit 1 }
$PatchedSha1 = Get-Sha1 $PatchedFile

# ---------------------------------------------------------------------------
# 3. 逐个安装
# ---------------------------------------------------------------------------
$installed = 0; $skipped = 0; $mismatch = 0; $failed = 0
foreach ($target in $targets) {
    Write-Step "处理: $target"
    $content = [System.IO.File]::ReadAllText($target)

    if ($content.Contains("pinnedSessions: {}")) {
        Write-Ok "已安装(检测到 pinnedSessions),跳过。"
        $skipped++; continue
    }

    $sha1 = Get-Sha1 $target
    $anchorsOk = $content.Contains('persist: "dsh.workspace.view.v5"') -and
                 $content.Contains('function deriveFlat(list, archivedSessionIds) {') -and
                 $content.Contains('"orderBy.updated": "最近更新"')

    if ($sha1 -eq $PristineSha1) {
        Write-Ok "哈希匹配原始版本,可以安全安装。"
    } elseif ($anchorsOk) {
        if ($Force) {
            Write-Warn "哈希不匹配但内容锚点匹配(可能为同代次不同构建),按 -Force 继续安装。"
        } else {
            Write-Warn "哈希不匹配但内容锚点匹配(可能为同代次不同构建)。"
            Write-Warn "如确认你的 DSH 版本为 $SupportedNote,请加 -Force 继续;"
            Write-Warn "否则跳过(不会改动你的文件)。"
            $mismatch++; continue
        }
    } else {
        Write-Fail "版本不匹配:目标文件既不是已知的原始版本,内容锚点也不符。"
        Write-Fail "预期支持版本:$SupportedNote"
        Write-Fail "你的文件 SHA1: $sha1"
        $mismatch++; continue
    }

    # 备份(幂等:已有备份则不覆盖)
    $bak = "$target.bak-dshpin"
    if (-not (Test-Path $bak)) {
        Copy-Item $target $bak -Force
        Write-Ok "已备份原文件 -> $bak"
    } else {
        Write-Ok "备份已存在,保留原备份: $bak"
    }

    # 写入补丁版(带重试,应对 DSH 仍在运行时文件被占用)
    $written = $false
    for ($i = 1; $i -le 5; $i++) {
        try {
            Copy-Item $PatchedFile $target -Force -ErrorAction Stop
            $written = $true; break
        } catch {
            if ($i -lt 5) { Start-Sleep -Milliseconds 800 }
            else {
                Write-Fail "写入失败(文件可能被运行中的 DSH 占用)。请完全退出 DSH 后重试。"
                Write-Fail "  $($_.Exception.Message)"
                $failed++; $written = $false
            }
        }
    }
    if (-not $written) { continue }

    # 回读校验
    $verify = Get-Sha1 $target
    if ($verify -eq $PatchedSha1) {
        Write-Ok "写入并校验成功。"
        $installed++
    } else {
        Write-Fail "写入后校验不一致!请用 uninstall.ps1 还原备份,或手动恢复 $bak"
        $failed++
    }
}

# ---------------------------------------------------------------------------
# 4. 汇总
# ---------------------------------------------------------------------------
Write-Step "完成"
Write-Ok "安装成功: $installed 处 | 已安装跳过: $skipped | 跳过(版本不符): $mismatch | 失败: $failed"
if ($installed -gt 0) {
    Write-Ok "接下来:"
    Write-Ok "  1. (重新)启动 DSH;"
    Write-Ok "  2. 刷新 Web 界面(如仍显示旧界面,按 Ctrl+Shift+R 强制刷新);"
    Write-Ok "  3. 悬停任意会话 -> 点击行内图钉按钮,或 ⋯ 菜单 -> 置顶会话;"
    Write-Ok "  4. 置顶的会话会出现在列表顶部「置顶」区块,再次点击可取消置顶。"
}
if ($mismatch -gt 0) {
    Write-Warn "有 $mismatch 处目标因版本不匹配未安装。请确认你的 DSH 版本,或联系仓库作者适配。"
}
if ($failed -gt 0) {
    Write-Warn "有 $failed 处目标安装失败,请检查上方错误信息。"
}
