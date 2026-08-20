#Requires -Version 5.1
<#
.SYNOPSIS
  DeepSeek Harness 桌面版 - 会话标题修复补丁应用脚本

.DESCRIPTION
  修复"重启 DSH 后左侧会话标题变成工作区目录名(如 deapseak_Harness),
  要点进会话才恢复真实标题"的问题。

  原因:侧栏标题来自"会话投影缓存"(session_projcache.json),该缓存在本
  版本存在写入卡死的问题(长期不落盘),冷启动时大量会话没有缓存标题,
  显示为工作区目录名。

  本补丁:在宿主 dsh-host-apiproxy 的会话列表下发逻辑里增加"标题兜底"——
  缓存里没有标题时,直接从会话日志折叠出标题补上(限制 2MB 以内、有记忆、
  失败自动降级,不影响其它功能)。

  脚本会:
  1. 结束正在运行的 DeepSeek Harness 进程
  2. 校验目标文件是否为受支持的原始版本(哈希门禁)
  3. 备份原文件为 index.js.bak-dshpintitle
  4. 用补丁版替换
  5. 校验
  6. 重新启动桌面应用

.PARAMETER AppDir
  可选。桌面应用安装目录(包含 DeepSeek Harness.exe)。默认自动定位。

.PARAMETER SkipRestart
  可选(仅测试用)。跳过"结束进程/重新启动"。

.PARAMETER Restore
  可选。还原模式:把备份复制回去(回滚补丁)。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install-title-fix.ps1
#>
[CmdletBinding()]
param(
    [string]$AppDir = "",
    [switch]$SkipRestart,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

# 受支持的"原版" dsh-host-apiproxy/lib/index.js 的 SHA1(DeepSeek Harness 桌面版 0.1.0-rc.5)
$OriginalSha1 = "28888b02df41931af6d74005735c08ca6eb1b7b2"
$SupportedNote = "DeepSeek Harness 桌面版 0.1.0-rc.5"

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    XX $m" -ForegroundColor Red }

function Find-DshApp {
    foreach ($base in @((Join-Path $env:LOCALAPPDATA "Programs"), ${env:ProgramFiles})) {
        $p = Join-Path $base "DeepSeek Harness"
        if (Test-Path (Join-Path $p "resources\app.asar")) { return $p }
    }
    foreach ($drive in @("C:", "D:", "E:")) {
        $users = Join-Path $drive "Users"
        if (-not (Test-Path $users)) { continue }
        foreach ($u in (Get-ChildItem $users -Directory -ErrorAction SilentlyContinue)) {
            $p = Join-Path $u.FullName "AppData\Local\Programs\DeepSeek Harness"
            if (Test-Path (Join-Path $p "resources\app.asar")) { return $p }
        }
    }
    return ""
}

$Rel = "resources\host\node_modules\@deepseek-ai\dsh-host-apiproxy\lib\index.js"

if (-not $AppDir) {
    $AppDir = Find-DshApp
    if (-not $AppDir) { Write-Fail "未找到 DeepSeek Harness 安装目录。请用 -AppDir 显式指定后重试。"; exit 1 }
}
$target = Join-Path $AppDir $Rel
$patched = Join-Path $PSScriptRoot "patched\dsh-host-apiproxy-index.js"
$bak = "$target.bak-dshpintitle"

Write-Step "目标文件: $target"
if (-not (Test-Path $target)) { Write-Fail "缺少 $target"; exit 1 }

if ($Restore) {
    if (-not (Test-Path $bak)) { Write-Fail "没有找到备份 $bak,无需还原。"; exit 1 }
    if (-not $SkipRestart) {
        Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    $ok = $false
    for ($i = 1; $i -le 8; $i++) {
        try { Copy-Item $bak $target -Force -ErrorAction Stop; $ok = $true; break }
        catch { if ($i -lt 8) { Start-Sleep -Milliseconds 900 } }
    }
    if (-not $ok) { Write-Fail "还原失败(文件被占用)。请退出所有 DSH 进程后重试。"; exit 1 }
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
    Write-Ok "已还原原始文件,并删除备份。"
    if (-not $SkipRestart) {
        Start-Process (Join-Path $AppDir "DeepSeek Harness.exe") -ErrorAction Stop
        Write-Ok "已重新启动 DSH。"
    }
    exit 0
}

if (-not (Test-Path $patched)) { Write-Fail "缺少补丁文件 $patched(请与脚本放在同一目录)"; exit 1 }

$txt = [System.IO.File]::ReadAllText($target)
if ($txt.Contains('coldTitleFor')) {
    Write-Ok "检测到已安装标题修复,无需重复打补丁。"
} else {
    $sha = (Get-FileHash $target -Algorithm SHA1).Hash.ToLower()
    if ($sha -ne $OriginalSha1) {
        Write-Fail "版本不匹配:当前文件不是受支持的 $SupportedNote 原版。"
        Write-Fail "你的文件 SHA1: $sha"
        Write-Fail "为避免损坏应用,已中止。请勿强制替换。"
        exit 1
    }
    if (-not $SkipRestart) {
        Write-Step "关闭正在运行的 DeepSeek Harness ..."
        Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    if (-not (Test-Path $bak)) {
        Copy-Item $target $bak -Force
        Write-Ok "已备份原文件 -> $bak"
    }
    $ok = $false
    for ($i = 1; $i -le 8; $i++) {
        try { Copy-Item $patched $target -Force -ErrorAction Stop; $ok = $true; break }
        catch { if ($i -lt 8) { Start-Sleep -Milliseconds 900 } }
    }
    if (-not $ok) { Write-Fail "替换失败(文件被占用)。请退出所有 DSH 进程后重试。"; exit 1 }
    $newTxt = [System.IO.File]::ReadAllText($target)
    if ($newTxt.Contains('coldTitleFor')) {
        Write-Ok "替换并校验成功(标题修复已生效)。"
    } else {
        Write-Fail "校验未通过!请用备份还原: Copy-Item '$bak' '$target' -Force"
        exit 1
    }
}
if (-not $SkipRestart) {
    Write-Step "重新启动 DeepSeek Harness ..."
    Start-Process (Join-Path $AppDir "DeepSeek Harness.exe") -ErrorAction Stop
    Write-Ok "已启动。重启后左侧会话将直接显示真实标题(不再显示工作区目录名)。"
} else {
    Write-Ok "(测试模式)跳过重新启动。"
}
