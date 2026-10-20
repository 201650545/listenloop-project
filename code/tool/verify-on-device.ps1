<#
.SYNOPSIS
    一键装机 + 真机验收（读页/听页）。

.DESCRIPTION
    把当前代码装到手机并做最小必要的真机验证：
      ① adb 无线调试连上（可用 -Device 参数指定）
      ② flutter build apk --debug
      ③ adb install -r
      ④ 冷启动 App
      ⑤ 截图存档到 scratch/真机截图/

    ⚠️ 装机前会**探物理内存**：使用率 ≥88% 且无 Gradle/Java 孤儿可清时
       会拒绝全量构建并提示先清理内存（AGENTS.md 规则 5）。

.EXAMPLE
    .\tool\verify-on-device.ps1 -Device 192.168.2.5:33217
    .\tool\verify-on-device.ps1 -Device 192.168.2.5:33217 -SkipBuild
#>
[CmdletBinding()]
param(
    [string]$Device = '',
    [switch]$SkipBuild,
    [switch]$KeepSession
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$adb = 'D:\android-sdk\platform-tools\adb.exe'
$flutter = 'D:\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { $flutter = (Get-Command flutter).Source }

# ── 1. 连设备 ────────────────────────────────────────────────
if ($Device) {
    Write-Host "[1/5] 连接 $Device"
    & $adb connect $Device
    Start-Sleep -Seconds 2
}
$devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' })
if ($devices.Count -eq 0) {
    Write-Host "[FAIL] 没有可用设备。手机要与本机同一 Wi-Fi 且开启无线调试。"
    Write-Host "       本机 IP: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'WLAN' } | Select-Object -First 1).IPAddress)"
    exit 1
}
$serial = ($devices[0] -split '\s+')[0]
Write-Host "      设备: $serial"

# ── 2. 探内存（规则 5）────────────────────────────────────────
$os = Get-CimInstance Win32_OperatingSystem
$total = $os.TotalVisibleMemorySize / 1MB
$free = $os.FreePhysicalMemory / 1MB
$used = [math]::Round(($total - $free) / $total * 100, 1)
Write-Host "[2/5] 内存使用率 ${used}%"

# ── 3. 构建 ─────────────────────────────────────────────────
if (-not $SkipBuild) {
    if ($used -ge 88) {
        $orphans = @(Get-Process -ErrorAction SilentlyContinue |
                     Where-Object { $_.ProcessName -match '^(java|dartvm|gradle)$' })
        if ($orphans.Count -gt 0) {
            Write-Host "      清理孤儿构建进程（$($orphans.Count) 个）"
            $orphans | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            $os = Get-CimInstance Win32_OperatingSystem
            $free = $os.FreePhysicalMemory / 1MB
            $used = [math]::Round(($total - $free) / $total * 100, 1)
            Write-Host "      清理后 ${used}%"
        }
        if ($used -gt 90) {
            Write-Host "[FAIL] 内存 ${used}% > 90%，暂停全量构建（规则 5）。"
            Write-Host "       先关掉浏览器/大内存程序再重试，或用 -SkipBuild 跳过构建。"
            exit 2
        }
    }
    Write-Host "[3/5] 构建 debug APK（首次约 3~4 分钟）"
    & $flutter build apk --debug
    if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] 构建失败"; exit 3 }
} else {
    Write-Host "[3/5] 跳过构建（-SkipBuild）"
}

# ── 4. 安装 + 冷启动 ─────────────────────────────────────────
$apk = 'build\app\outputs\flutter-apk\app-debug.apk'
if (-not (Test-Path $apk)) { Write-Host "[FAIL] 没有 APK：$apk"; exit 4 }
Write-Host "[4/5] 安装"
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) { Write-Host "[FAIL] 安装失败"; exit 5 }

Write-Host "      冷启动"
& $adb -s $serial shell am force-stop com.phrasing.phrasing
& $adb -s $serial shell monkey -p com.phrasing.phrasing -c android.intent.category.LAUNCHER 1 | Out-Null
Start-Sleep -Seconds 6

# ── 5. 截图存档 ──────────────────────────────────────────────
$shotDir = Join-Path $repo 'scratch\真机截图'
New-Item -ItemType Directory -Force $shotDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$png = Join-Path $shotDir "readpage-$stamp.png"
& $adb -s $serial shell screencap -p /sdcard/_ll.png
& $adb -s $serial pull /sdcard/_ll.png $png | Out-Null
& $adb -s $serial shell rm /sdcard/_ll.png
Write-Host "[5/5] 截图 → $png"
Write-Host ""
Write-Host "==== 真机验收清单（对着截图逐条看） ===="
Write-Host "  读页：① 整篇课文都显示（不是只有一句）② 灰色形状跟着当前句"
Write-Host "        ③ 定位区句号与灰块所在句一致"
Write-Host "  听页：④ 灰色形状跟随当前句（不是钉在屏幕中线的固定块）"
Write-Host "        ⑤ 顶栏右槽按钮不溢出"
Write-Host "  查看全部截图：explorer `"$shotDir`""
exit 0
