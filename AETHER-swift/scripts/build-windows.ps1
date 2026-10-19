$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Configuration = if ($env:CONFIGURATION) { $env:CONFIGURATION } else { "release" }
$SdkRoot = if ($env:WEBVIEW2_SDK_DIR) {
    [System.IO.Path]::GetFullPath($env:WEBVIEW2_SDK_DIR)
} else {
    Join-Path $Root ".build\dependencies\Microsoft.Web.WebView2"
}
if (-not (Test-Path (Join-Path $SdkRoot "build\native\include\WebView2.h"))) {
    & (Join-Path $PSScriptRoot "install-webview2-sdk.ps1")
}
if (-not (Test-Path (Join-Path $SdkRoot "build\native\include\WebView2.h"))) {
    throw "WebView2 SDK headers are missing at $SdkRoot. Set WEBVIEW2_SDK_DIR or rerun the installer."
}

swift build -c $Configuration --product AETHER
if ($LASTEXITCODE -ne 0) { throw "SwiftPM failed to build AETHER." }

$BinPath = (swift build -c $Configuration --product AETHER --show-bin-path).Trim()
if ($LASTEXITCODE -ne 0) { throw "Could not locate the SwiftPM build output." }
$Binary = Join-Path $BinPath "AETHER.exe"
if (-not (Test-Path $Binary)) { $Binary = Join-Path $BinPath "AETHER" }
if (-not (Test-Path $Binary)) { throw "SwiftPM did not produce the AETHER executable." }

$OutputDirectory = Join-Path $Root "dist/windows"
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$Output = Join-Path $OutputDirectory "AETHER.exe"
Copy-Item -Force $Binary $Output
Write-Output "Built: $Output"
