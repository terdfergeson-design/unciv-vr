param(
	[string]$GodotPath = $env:GODOT,
	[string]$JdkHome = $env:JAVA_HOME
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$client = Join-Path $repo "client"
$unciv = Join-Path $repo "unciv"
$buildRoot = Join-Path $repo "build\windows"
$package = Join-Path $buildRoot "UncivVR"
# One version for both builds: the Quest preset's version/name in client\export_presets.cfg
$versionLine = Select-String -LiteralPath (Join-Path $client "export_presets.cfg") -Pattern '^version/name="(.+)"' | Select-Object -First 1
if (-not $versionLine) { throw "Can't read version/name from client\export_presets.cfg" }
$version = $versionLine.Matches[0].Groups[1].Value
$zip = Join-Path $buildRoot "UncivVR-v$version-windows.zip"
Write-Host "Unciv VR $version for Windows"

if (-not $GodotPath) {
	$GodotPath = Join-Path $env:USERPROFILE "Documents\Godot_v4.7.2-stable_win64.exe"
}
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
	throw "Godot executable not found: $GodotPath. Pass -GodotPath or set GODOT."
}
if (-not $JdkHome) {
	$foundJlink = Get-Command jlink.exe -ErrorAction SilentlyContinue
	if ($foundJlink) { $JdkHome = Split-Path (Split-Path $foundJlink.Source -Parent) -Parent }
}
if (-not $JdkHome -or -not (Test-Path -LiteralPath (Join-Path $JdkHome "bin\jlink.exe"))) {
	throw "A JDK 21 is required to build the trimmed runtime. Set JAVA_HOME or pass -JdkHome."
}

$gradle = Join-Path $unciv "gradlew.bat"
$assets = Join-Path $unciv "android\assets"
if (-not (Test-Path -LiteralPath $gradle -PathType Leaf) -or -not (Test-Path -LiteralPath (Join-Path $unciv "bridge") -PathType Container)) {
	throw "The Unciv submodule is missing. From the repository root run: git submodule update --init --recursive"
}
if (-not (Test-Path -LiteralPath $assets -PathType Container)) { throw "Unciv assets not found: $assets" }

New-Item -ItemType Directory -Force -Path $buildRoot | Out-Null
# This script owns only this generated package directory and archive.
if (Test-Path -LiteralPath $package) { Remove-Item -LiteralPath $package -Recurse -Force }
if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
$oldZip = Join-Path $buildRoot "UncivVR-Windows-x86_64.zip"   # the name used before versioned zips
if (Test-Path -LiteralPath $oldZip) { Remove-Item -LiteralPath $oldZip -Force }
New-Item -ItemType Directory -Force -Path $package | Out-Null

function Invoke-Godot([string]$Arguments, [string]$Description) {
	Write-Host $Description
	$process = Start-Process -FilePath $GodotPath -ArgumentList $Arguments -Wait -PassThru -WindowStyle Hidden
	if ($process.ExitCode -ne 0) { throw "$Description failed with exit code $($process.ExitCode)." }
}

Write-Host "Building the self-contained Unciv bridge..."
Push-Location $unciv
try {
	& $gradle :bridge:dist --no-daemon --console=plain
	if ($LASTEXITCODE -ne 0) { throw "Gradle bridge build failed with exit code $LASTEXITCODE." }
} finally { Pop-Location }
$bridgeJar = Join-Path $unciv "bridge\build\libs\UncivBridge.jar"
if (-not (Test-Path -LiteralPath $bridgeJar -PathType Leaf)) { throw "Gradle did not produce $bridgeJar" }

$packArgs = '--headless --xr-mode off --path "' + $client + '" -s tools/pack_android_data.gd'
Invoke-Godot $packArgs "Packing Unciv and built-in game data..."
if (-not (Test-Path -LiteralPath (Join-Path $client "android_data.pack") -PathType Leaf)) {
	throw "Godot did not create client\android_data.pack."
}

$importArgs = '--headless --xr-mode off --path "' + $client + '" --import'
Invoke-Godot $importArgs "Importing packed game data into the Godot project..."

$exe = Join-Path $package "UncivVR.exe"
$godotArgs = @('--headless', '--xr-mode', 'off', '--path', '"' + $client + '"', '--export-release', '"Windows Desktop"', '"' + $exe + '"') -join ' '
Invoke-Godot $godotArgs "Exporting the Godot Windows build..."
if (-not (Test-Path -LiteralPath (Join-Path $package "UncivVR.exe") -PathType Leaf)) { throw "Godot did not create the Windows executable." }
$packSize = (Get-Item -LiteralPath (Join-Path $client "android_data.pack")).Length
$exportedPack = Join-Path $package "UncivVR.pck"
if (-not (Test-Path -LiteralPath $exportedPack -PathType Leaf)) {
	throw "The Windows export is missing android_data.pack. Reimport the project and export again."
}
$pckText = [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($exportedPack))
if (-not $pckText.Contains("android_data.pack") -or (Get-Item -LiteralPath $exportedPack).Length -lt $packSize) {
	throw "The Windows export is missing android_data.pack. Reimport the project and export again."
}

$bridgeDir = Join-Path $package "bridge"
New-Item -ItemType Directory -Force -Path $bridgeDir | Out-Null
Copy-Item -LiteralPath $bridgeJar -Destination (Join-Path $bridgeDir "UncivBridge.jar")

Write-Host "Finding the Java modules used by the bridge..."
$jdeps = Join-Path $JdkHome "bin\jdeps.exe"
$jlink = Join-Path $JdkHome "bin\jlink.exe"
$moduleLines = & $jdeps --multi-release 21 --ignore-missing-deps --print-module-deps $bridgeJar 2>$null
if ($LASTEXITCODE -ne 0) { throw "jdeps could not analyze the bridge JAR." }
$modules = ($moduleLines | Where-Object { $_ -match '^[A-Za-z0-9_.]+(,[A-Za-z0-9_.]+)*$' } | Select-Object -Last 1)
if (-not $modules) { throw "jdeps returned no Java module list for the bridge." }

Write-Host "Creating a trimmed Java runtime ($modules)..."
$runtime = Join-Path $package "runtime"
& $jlink --module-path (Join-Path $JdkHome "jmods") --add-modules $modules --strip-debug --no-header-files --no-man-pages --compress=2 --output $runtime
if ($LASTEXITCODE -ne 0) { throw "jlink failed with exit code $LASTEXITCODE." }
if (-not (Test-Path -LiteralPath (Join-Path $runtime "bin\java.exe") -PathType Leaf)) { throw "The trimmed runtime is missing java.exe." }

Copy-Item -LiteralPath (Join-Path $repo "LICENSE") -Destination $package
Copy-Item -LiteralPath (Join-Path $repo "CREDITS.md") -Destination $package
@"
Unciv VR $version for Windows x86_64

Run UncivVR.exe. The portable package includes the Unciv game engine and a trimmed Java runtime; Java and Godot do not need to be installed. Game data is unpacked to the user's Godot data folder on first launch.
Saves and settings are stored in your user profile under .unciv-vr.

For license and attribution information, see LICENSE and CREDITS.md.
"@ | Set-Content -LiteralPath (Join-Path $package "README.txt") -Encoding UTF8

Write-Host "Creating the portable ZIP..."
Compress-Archive -Path (Join-Path $package "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Created $package"
Write-Host "Created $zip"
