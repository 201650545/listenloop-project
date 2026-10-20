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
    [switch]$AutoDiscover,
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

# 自动发现：手机在同网段但 adb 没连上 ⇒ 扫同网段的常见无线调试端口。
# ⚠️ 2026-10-21 实测：手机给的地址 192.168.2.5:33217 与本机 192.168.128.x
#    **不同网段**，路由表里没有到 192.168.2.x 的路由 ⇒ 无论重试多少次都连不上
#    （ping 也不通）。这不是 adb 的问题，是**两个网段不通**。
#    ⇒ 手机必须连到本机所在的 192.168.128.x 那个 Wi-Fi。
if ($devices.Count -eq 0 -and $AutoDiscover) {
    $myIp = (Get-NetIPAddress -AddressFamily IPv4 |
             Where-Object { $_.InterfaceAlias -eq 'WLAN' } |
             Select-Object -First 1).IPAddress
    $prefix = ($myIp -split '\.')[0..2] -join '.'
    Write-Host "      自动扫描 $prefix.0/24 的常见 adb 端口…"
    foreach ($last in 1..254) {
        $ip = "$prefix.$last"
        if ($ip -eq $myIp) { continue }
        foreach ($port in @(5555)) {
            $probe = Test-NetConnection -ComputerName $ip -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
            if ($probe) {
                $out = & $adb connect "$ip`:$port" 2>&1
                if ("$out" -match 'connected') {
                    Write-Host "      找到设备 $ip`:$port"
                    $devices = @(& $adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' })
                    break
                }
            }
        }
        if ($devices.Count -gt 0) { break }
    }
}

if ($devices.Count -eq 0) {
    Write-Host "[FAIL] 没有可用设备。"
    Write-Host "       ⇒ 手机必须与本机在**同一网段**（本机 WLAN: $((Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -eq 'WLAN' } | Select-Object -First 1).IPAddress)）"
    Write-Host "       ⇒ 且开启「无线调试」。给到正确地址后重跑："
    Write-Host "          .\tool\verify-on-device.ps1 -Device <ip:port>"
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
