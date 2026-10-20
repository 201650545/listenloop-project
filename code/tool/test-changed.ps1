<#
.SYNOPSIS
    只跑「受影响」的测试，而不是每次全量。

.DESCRIPTION
    2026-10-21（GPT 镜像站评审后的落地）：
    日常改 UI 不该每次跑整套 test/（30 秒以上）。本脚本按**目录约定**做保守
    裁剪：

      · 改了 lib/<dir>/... ⇒ 跑 test/<dir>/（本仓 lib/ 与 test/ 顶层目录一一
        对应：widgets / screens / training / storage / models / …）
      · 改了 lib/ 下的**共享**层（theme/、utils/、l10n/、data/ 等）⇒ 影响面
        太大，直接跑全量
      · 改了测试文件本身 ⇒ 跑那一个文件
      · 动了 pubspec.yaml / 原生代码 ⇒ 直接跑全量

    ⚠️ 这是**按约定目录**的保守裁剪，不是精确的 Dart import 依赖分析。
      跨目录导入仍可能漏测 ⇒ 全量测试仍是提交前/里程碑前的最终关卡。

.PARAMETER Full
    强制跑全量（等价于 flutter test）。

.PARAMETER UpdateGoldens
    透传给 flutter test：更新 golden 基准图。
    ⚠️ 不要当日常命令用 —— 每次改坏 UI 都自动更新基准，golden 就失去防回归意义。

.EXAMPLE
    .\tool\test-changed.ps1
    .\tool\test-changed.ps1 -Full
#>
[CmdletBinding()]
param(
    [switch]$Full,
    [switch]$UpdateGoldens
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

# ── 找 flutter（不依赖调用者的 PATH） ─────────────────────────────
function Resolve-Flutter {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    # 本机默认 SDK 位置（可用 $env:FLUTTER_ROOT 覆盖）
    $candidates = @()
    if ($env:FLUTTER_ROOT) { $candidates += (Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat') }
    $candidates += 'D:\flutter\bin\flutter.bat'
    $candidates += 'C:\src\flutter\bin\flutter.bat'
    $candidates += (Join-Path $env:LOCALAPPDATA 'flutter\bin\flutter.bat')
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return $c }
    }
    throw '找不到 flutter：不在 PATH，也不在已知位置。请设 $env:FLUTTER_ROOT。'
}
$flutter = Resolve-Flutter
Write-Host "flutter: $flutter"

# ── 1. 收集改动文件 ────────────────────────────────────────────────
# ⚠️ git 会把 LF/CRLF 警告写进 stderr；本仓有 CRLF 混用，警告很多。
#    用 -c core.safecrlf=false 关掉该警告，并且**不重定向 stderr**
#    （$ErrorActionPreference='Stop' 下 2>$null 会把 warning 变成终止错误）。
function Get-GitLines([string[]]$gitArgs) {
    $out = & git -c core.safecrlf=false @gitArgs
    if (-not $out) { return @() }
    return @($out | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
}

$changed = @()
$changed += Get-GitLines @('diff', '--name-only', 'HEAD', '--', 'lib', 'test')
$changed += Get-GitLines @('diff', '--name-only', '--cached', '--', 'lib', 'test')
$changed += Get-GitLines @('ls-files', '--others', '--exclude-standard', '--', 'lib', 'test')
$changed = @($changed | Where-Object { $_ } | Sort-Object -Unique)

# pubspec / 原生代码变了 ⇒ 全量
$structural = @()
$structural += Get-GitLines @('diff', '--name-only', 'HEAD', '--', 'pubspec.yaml', 'pubspec.lock', 'android', 'ios', 'windows')
$structural += Get-GitLines @('ls-files', '--others', '--exclude-standard', '--', 'pubspec.yaml', 'android', 'ios', 'windows')
if ($structural.Count -gt 0) {
    Write-Host "[FULL] 结构性改动：$($structural -join ', ')"
    $Full = $true
}

if ($changed.Count -eq 0) {
    Write-Host "没有改动，无需测试。"
    exit 0
}

Write-Host "改动文件（$($changed.Count)）："
$changed | ForEach-Object { Write-Host "  $_" }

# flutter test 的附加参数
$extraArgs = @()
if ($UpdateGoldens) {
    Write-Host "[GOLDEN] 更新基准图（注意：会覆盖旧基准，日常别用）"
    $extraArgs += '--update-goldens'
}

if ($Full) {
    Write-Host "`n[FULL] 跑全量测试"
    & $flutter test @extraArgs
    exit $LASTEXITCODE
}

# ── 2. 映射到测试 ────────────────────────────────────────────────
$targets = New-Object System.Collections.Generic.List[string]
$runAll = $false

foreach ($file in $changed) {
    $norm = $file -replace '\\', '/'

    # 测试目录下的**非 .dart** 资源（golden 基线图、失败快照 png）⇒ 忽略，
    # 它们不是测试代码。
    if ($norm -match '^test/.+' -and $norm -notmatch '\.dart$') { continue }

    # 测试文件本身 ⇒ 跑它自己
    if ($norm -match '^test/(.+)\.dart$') {
        $targets.Add($norm)
        continue
    }
    # lib/<dir>/... ⇒ test/<dir>/
    if ($norm -match '^lib/([^/]+)/') {
        $dir = $Matches[1]
        # 共享层：改动影响面大 ⇒ 全量。
        # ⚠️ dev/ 是**独立预览入口**，不参与 App 运行 ⇒ 不算共享层。
        $shared = @('theme', 'utils', 'l10n', 'data', 'interaction')
        if ($shared -contains $dir) {
            Write-Host "[FULL] 共享层改动：$dir"
            $runAll = $true
            continue
        }
        # dev/ 是独立预览入口（不进 App），没有也不需要测试 ⇒ 跳过。
        if ($dir -eq 'dev') { continue }
        $testDir = "test/$dir"
        if (Test-Path $testDir) {
            $targets.Add($testDir)
        } else {
            Write-Host "[FULL] 没有对应的测试目录：$dir"
            $runAll = $true
        }
        continue
    }
    # lib/ 根目录的文件（main.dart 等）⇒ 全量
    Write-Host "[FULL] 根部文件改动：$norm"
    $runAll = $true
}

if ($runAll) {
    Write-Host "`n[FULL] 跑全量测试"
    & $flutter test
    exit $LASTEXITCODE
}

$targets = @($targets | Sort-Object -Unique)
if ($targets.Count -eq 0) {
    Write-Host "没有可裁剪的测试目标，跑全量。"
    & $flutter test
    exit $LASTEXITCODE
}

Write-Host "`n[裁剪] 只跑：$($targets -join ', ')"
& $flutter test @targets
exit $LASTEXITCODE
