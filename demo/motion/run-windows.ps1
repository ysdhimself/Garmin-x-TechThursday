<#
.SYNOPSIS
  Build and run the motion demo (or its tests) in the Connect IQ simulator on Windows.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1
  powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1 -Test
  powershell -ExecutionPolicy Bypass -File demo\motion\run-windows.ps1 -Device fenix7s -Key C:\keys\developer_key
#>
param(
    [string]$Device = "fenix7",
    [string]$Key = $env:GARMIN_DEVELOPER_KEY,
    [switch]$Test
)
$ErrorActionPreference = "Stop"

$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$ciq = Join-Path $env:APPDATA "Garmin\ConnectIQ"

# Active SDK, as selected in Garmin SDK Manager ("Use as SDK").
$sdk = (Get-Content (Join-Path $ciq "current-sdk.cfg")).Trim()
$bin = Join-Path $sdk "bin"
if (-not (Test-Path "$bin\monkeyc.bat")) { throw "No monkeyc.bat in $bin. Pick an SDK in SDK Manager." }

if (-not (Test-Path (Join-Path $ciq "Devices\$Device\compiler.json"))) {
    throw "Device profile '$Device' missing. Download it in SDK Manager > Devices."
}

# Signing key: -Key, then GARMIN_DEVELOPER_KEY, then the VS Code Monkey C setting.
if (-not $Key) {
    $vs = Join-Path $env:APPDATA "Code\User\settings.json"
    if (Test-Path $vs) {
        $m = Select-String -Path $vs -Pattern '"monkeyC\.developerKeyPath"\s*:\s*"([^"]+)"' | Select-Object -First 1
        if ($m) { $Key = $m.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
}
if (-not $Key -or -not (Test-Path $Key)) {
    throw "Developer key not found. Pass -Key, set GARMIN_DEVELOPER_KEY, or set monkeyC.developerKeyPath in VS Code."
}

$out = Join-Path $root ".amp\in\build"
New-Item -ItemType Directory -Force $out | Out-Null
$name = if ($Test) { "motion-tests.prg" } else { "motion-demo.prg" }
$prg = Join-Path $out $name

$buildArgs = @("-f", "$root\demo\motion\monkey.jungle", "-d", $Device, "-o", $prg, "-y", $Key)
if ($Test) { $buildArgs += "-t" }
& "$bin\monkeyc.bat" @buildArgs
if ($LASTEXITCODE -ne 0) { throw "Build failed." }

# Start the simulator if it is not already running.
if (-not (Get-Process simulator -ErrorAction SilentlyContinue)) {
    Start-Process "$bin\simulator.exe"
    Start-Sleep -Seconds 6
}

# Note: Windows monkeydo takes /t, not -t.
if ($Test) { & "$bin\monkeydo.bat" $prg $Device /t } else { & "$bin\monkeydo.bat" $prg $Device }
exit $LASTEXITCODE
