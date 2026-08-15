#Requires -Version 5.1
<#
.SYNOPSIS
  DSH 左侧工作区「会话置顶」增强 - 卸载/还原脚本

.DESCRIPTION
  将安装脚本备份的原始 lib/client.js(备份名为 client.js.bak-dshpin)
  还原回去,移除「会话置顶」增强。

.PARAMETER DshRoot
  可选。与 install.ps1 相同,显式指定 DSH 宿主安装根目录。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File uninstall.ps1
#>
[CmdletBinding()]
param([string]$DshRoot = "")

$ErrorActionPreference = "Stop"

$Rel = "node_modules\@deepseek-ai\dsh-client-ui-workspace\lib\client.js"

function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "    $msg" -ForegroundColor Green }
function Write-Fail($msg) { Write-Host "    XX $msg" -ForegroundColor Red }

# 与 install.ps1 相同的目标定位逻辑
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
$profileCopy = Join-Path $env:USERPROFILE ".dsh\profiles\node_modules\@deepseek-ai\dsh-client-ui-workspace\lib\client.js"
if (Test-Path $profileCopy) { $candidates.Add($profileCopy) }

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

$restored = 0; $none = 0
foreach ($target in $targets) {
    Write-Step "处理: $target"
    $bak = "$target.bak-dshpin"
    if (-not (Test-Path $bak)) {
        Write-Ok "未找到备份($bak),跳过。"
        $none++; continue
    }
    for ($i = 1; $i -le 5; $i++) {
        try {
            Copy-Item $bak $target -Force -ErrorAction Stop
            break
        } catch {
            if ($i -lt 5) { Start-Sleep -Milliseconds 800 }
            else {
                Write-Fail "还原失败(文件可能被运行中的 DSH 占用)。请完全退出 DSH 后重试。"
                Write-Fail "  $($_.Exception.Message)"
            }
        }
    }
    if (Test-Path $bak) {
        # 还原后备份已无用,删除
        Remove-Item $bak -Force -ErrorAction SilentlyContinue
        Write-Ok "已还原原始文件,并删除备份。"
        $restored++
    } else {
        Write-Ok "还原完成。"
        $restored++
    }
}

Write-Step "完成"
Write-Ok "还原: $restored 处 | 无备份跳过: $none 处"
Write-Ok "请重启 DSH / 刷新界面,置顶功能即被移除(置顶数据保存在浏览器本地,不影响会话本身)。"
