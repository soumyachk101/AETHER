$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$SdkDirectory = if ($env:WEBVIEW2_SDK_DIR) {
    [System.IO.Path]::GetFullPath($env:WEBVIEW2_SDK_DIR)
} else {
    Join-Path $Root "AETHER-swift/.build/dependencies/Microsoft.Web.WebView2"
}
$Version = "1.0.2903.40"
$Package = Join-Path ([System.IO.Path]::GetTempPath()) "Microsoft.Web.WebView2.$Version.nupkg"
$Archive = "$Package.zip"
$Url = "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$Version"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $SdkDirectory) | Out-Null
Invoke-WebRequest -Uri $Url -OutFile $Package
Copy-Item -Force $Package $Archive
if (Test-Path $SdkDirectory) { Remove-Item -Recurse -Force $SdkDirectory }
New-Item -ItemType Directory -Force -Path $SdkDirectory | Out-Null
Expand-Archive -Path $Archive -DestinationPath $SdkDirectory -Force
Remove-Item -Force $Package, $Archive
Write-Output "WebView2 SDK $Version installed at $SdkDirectory"
