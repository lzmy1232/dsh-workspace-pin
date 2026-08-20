#Requires -Version 5.1
<#
.SYNOPSIS
  DeepSeek Harness 桌面端 - 固定端口补丁应用脚本

.DESCRIPTION
  把桌面端每次启动随机端口(--port 0)改为固定端口 9860,这样
  置顶、主题等所有浏览器本地偏好重启后都能保留(localStorage 按端口隔离)。

  脚本会:
  1. 结束正在运行的 DeepSeek Harness 进程
  2. 备份原 app.asar 为 app.asar.bak-dshport
  3. 用补丁版 app.asar(app-patched.asar)替换
  4. 校验替换结果
  5. 重新启动桌面应用(新地址: http://127.0.0.1:9860)

.PARAMETER AppDir
  可选。桌面应用安装目录(包含 DeepSeek Harness.exe 与 resources\app.asar)。
  默认自动定位。

.PARAMETER SkipRestart
  可选(仅测试用)。跳过"结束进程/重新启动",只做备份+替换+校验。

.PARAMETER Restore
  可选。还原模式:把备份的 app.asar.bak-dshport 复制回 app.asar(回滚补丁)。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File fix-desktop-port.ps1
#>
[CmdletBinding()]
param(
    [string]$AppDir = "",
    [switch]$SkipRestart,
    [switch]$Restore
)

$ErrorActionPreference = "Stop"

# 受支持的"原版" app.asar 的 SHA1(DeepSeek Harness 桌面版 0.1.0-rc.5)
$OriginalAsarSha1 = "8b74eda00b53ac4c6d5ec37d5b47ad74c0759c51"
$SupportedNote = "DeepSeek Harness 桌面版 0.1.0-rc.5"

function Write-Step($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    $m" -ForegroundColor Green }
function Write-Fail($m) { Write-Host "    XX $m" -ForegroundColor Red }

# ---- 全盘定位安装目录 ----
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
if (-not $AppDir) {
    $AppDir = Find-DshApp
    if (-not $AppDir) {
        Write-Fail "未找到 DeepSeek Harness 安装目录。请用 -AppDir 显式指定后重试。"
        exit 1
    }
}
$asar = Join-Path $AppDir "resources\app.asar"
$exe  = Join-Path $AppDir "DeepSeek Harness.exe"
$patched = Join-Path $PSScriptRoot "app-patched.asar"
$bak = "$asar.bak-dshport"

Write-Step "安装目录: $AppDir"
if (-not (Test-Path $asar)) { Write-Fail "缺少 $asar"; exit 1 }

# ---- 还原模式 ----
if ($Restore) {
    if (-not (Test-Path $bak)) { Write-Fail "没有找到备份文件 $bak,无需还原。"; exit 1 }
    if (-not $SkipRestart) {
        Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    }
    $ok = $false
    for ($i = 1; $i -le 8; $i++) {
        try { Copy-Item $bak $asar -Force -ErrorAction Stop; $ok = $true; break }
        catch { if ($i -lt 8) { Start-Sleep -Milliseconds 900 } }
    }
    if (-not $ok) { Write-Fail "还原失败(文件被占用)。请退出所有 DSH 进程后重试。"; exit 1 }
    Remove-Item $bak -Force -ErrorAction SilentlyContinue
    Write-Ok "已还原原始 app.asar,并删除备份。"
    if (-not $SkipRestart) {
        Start-Process $exe -ErrorAction Stop
        Write-Ok "已重新启动 DSH(随机端口,与最初一致)。"
    }
    exit 0
}

if (-not (Test-Path $patched)) { Write-Fail "缺少补丁文件 $patched(请与脚本放在同一目录)"; exit 1 }
if (-not (Test-Path $exe)) { Write-Fail "缺少 $exe"; exit 1 }

# ---- 检查是否已打过补丁 ----
$current = [System.IO.File]::ReadAllBytes($asar)
$txt = [System.Text.Encoding]::UTF8.GetString($current)
if ($txt.Contains('9860')) {
    Write-Ok "检测到已使用固定端口 9860,无需重复打补丁。"
} else {
    # ---- 版本门禁:目标必须是受支持的"原版" ----
    $sha = (Get-FileHash $asar -Algorithm SHA1).Hash.ToLower()
    if ($sha -ne $OriginalAsarSha1) {
        Write-Fail "版本不匹配:当前 app.asar 不是受支持的 $SupportedNote 原版。"
        Write-Fail "你的文件 SHA1: $sha"
        Write-Fail "为避免损坏应用,已中止。请勿强制替换。"
        exit 1
    }
    # ---- 结束运行中的进程 ----
    if (-not $SkipRestart) {
        Write-Step "关闭正在运行的 DeepSeek Harness ..."
        Get-Process -Name "DeepSeek Harness" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
    } else {
        Write-Step "(测试模式)跳过结束进程。"
    }

    # ---- 备份 ----
    $bak = "$asar.bak-dshport"
    if (-not (Test-Path $bak)) {
        Copy-Item $asar $bak -Force
        Write-Ok "已备份原文件 -> $bak"
    } else {
        Write-Ok "备份已存在,保留: $bak"
    }

    # ---- 替换(带重试) ----
    $ok = $false
    for ($i = 1; $i -le 8; $i++) {
        try {
            Copy-Item $patched $asar -Force -ErrorAction Stop
            $ok = $true; break
        } catch {
            if ($i -lt 8) { Start-Sleep -Milliseconds 900 }
        }
    }
    if (-not $ok) { Write-Fail "替换失败(文件被占用)。请确认所有 DSH 窗口/进程已退出后重试。"; exit 1 }

    # ---- 校验 ----
    $newBytes = [System.IO.File]::ReadAllBytes($asar)
    $newTxt = [System.Text.Encoding]::UTF8.GetString($newBytes)
    $oldPortGone = -not [regex]::IsMatch($newTxt, '"--port",\s*\r?\n\s*"0"')
    if ($newTxt.Contains('9860') -and $oldPortGone) {
        Write-Ok "替换并校验成功(已固定端口 9860)。"
    } else {
        Write-Fail "校验未通过!请用备份还原: Copy-Item '$bak' '$asar' -Force"
        exit 1
    }
}

# ---- 重新启动 ----
if ($SkipRestart) {
    Write-Ok "(测试模式)跳过重新启动。替换完成。"
} else {
    Write-Step "重新启动 DeepSeek Harness ..."
    Start-Process $exe -ErrorAction Stop
    Write-Ok "已启动。请稍候,新地址: http://127.0.0.1:9860"
    Write-Ok "打开后重新置顶一次即可,以后重启都会保留。"
    Write-Ok "(如需还原: 退出应用后,把 app.asar.bak-dshport 复制回 app.asar)"
}
