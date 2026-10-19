# Builds the OpenDots desktop shell for Windows (PowerShell 5+).
# Usage:
#   .\scripts\build-windows.ps1
#   .\scripts\build-windows.ps1 -Sign -CertificatePath C:\path\to\cert.pfx
[CmdletBinding()]
param(
    [switch]$Sign,
    [string]$CertificatePath,
    [string]$TimestampUrl = "http://timestamp.digicert.com"
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectDir = Split-Path -Parent $ScriptDir
$DistDir = Join-Path $ProjectDir "dist\windows"
$ReleaseDir = Join-Path $ProjectDir "dist\release"
$WebDir = Join-Path (Split-Path -Parent $ProjectDir) "AETHER-web"
$Version = (Select-String -Path (Join-Path $ProjectDir "Cargo.toml") -Pattern '^version = "([^"]+)"' | Select-Object -First 1).Matches.Groups[1].Value

Set-Location $ProjectDir

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo was not found in PATH. Install Rust 1.85+ from https://rustup.rs."
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "npm was not found in PATH. Install Node.js 24+."
}

Write-Host "==> Building OpenDots web app"
Push-Location $WebDir
try {
    & npm ci
    if ($LASTEXITCODE -ne 0) { throw "npm ci failed with exit code $LASTEXITCODE." }
    & npm run build
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

Write-Host "==> Building dibi-aether (release)"
if (-not $env:CMAKE_POLICY_VERSION_MINIMUM) {
    $env:CMAKE_POLICY_VERSION_MINIMUM = "3.5"
}
& cargo build --release
if ($LASTEXITCODE -ne 0) {
    throw "cargo build --release failed with exit code $LASTEXITCODE."
}

$BuiltExe = Join-Path $ProjectDir "target\release\aether.exe"
if (-not (Test-Path $BuiltExe)) {
    throw "Expected binary not found: $BuiltExe"
}

Write-Host "==> Assembling bundle in $DistDir"
if (Test-Path $DistDir) {
    Remove-Item -Path $DistDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$TargetExe = Join-Path $DistDir "AETHER.exe"
Copy-Item -Path $BuiltExe -Destination $TargetExe -Force

$WebBundle = Join-Path $DistDir "AETHER-web"
New-Item -ItemType Directory -Path $WebBundle -Force | Out-Null
Copy-Item (Join-Path $WebDir "package.json"), (Join-Path $WebDir "package-lock.json") -Destination $WebBundle
Copy-Item (Join-Path $WebDir "dist") -Destination (Join-Path $WebBundle "dist") -Recurse
Push-Location $WebBundle
try {
    & npm ci --omit=dev
    if ($LASTEXITCODE -ne 0) { throw "npm ci --omit=dev failed with exit code $LASTEXITCODE." }
}
finally { Pop-Location }

$Readme = @'
dibi AETHER (Windows)
=====================

Run:
  .\AETHER.exe

The app starts the OpenDots Node server on 127.0.0.1:4310 and stops it on exit.
The bundled OpenDots server and web app are included in AETHER-web\.

Requirements: Node.js 24+ in PATH. Configure provider credentials and options
in AETHER-web\.env as needed. Voice calls use the system default microphone and speaker. The native egui app does
not require the WebView2 Runtime.

Environment overrides:
  OPENDOTS_ROOT   Override the bundled OpenDots root (contains package.json and dist\)
  AETHER_URL      Attach to an existing server instead of starting one
  AETHER_PORT     Port for the local server (default 4310; PORT also works)
  OWNER_TOKEN     Owner token forwarded to the server

Log:
  %LOCALAPPDATA%\dibi-aether\server.log

There is no installer; this folder is portable. Keep AETHER.exe alongside
AETHER-web\ when moving the bundle.
'@
Set-Content -Path (Join-Path $DistDir "README.txt") -Value $Readme -Encoding ASCII

if ($Sign) {
    if (-not $CertificatePath -or -not (Test-Path $CertificatePath)) {
        Write-Warning "Signing requested but -CertificatePath was not provided or does not exist; skipping."
    }
    else {
        $SignTool = Get-Command signtool.exe -ErrorAction SilentlyContinue
        if (-not $SignTool) {
            $Candidates = Get-ChildItem -Path "${env:ProgramFiles(x86)}\Windows Kits\10\bin" `
                -Filter signtool.exe -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match '\\x64\\' } |
                Sort-Object FullName -Descending
            if ($Candidates) {
                $SignTool = $Candidates[0]
            }
        }

        if (-not $SignTool) {
            Write-Warning "signtool.exe was not found; skipping signing (the build is still usable)."
        }
        else {
            $SignToolPath = if ($SignTool.Source) { $SignTool.Source } else { $SignTool.FullName }
            Write-Host "==> Signing $TargetExe"
            & $SignToolPath sign /fd SHA256 /td SHA256 /tr $TimestampUrl /f $CertificatePath $TargetExe
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "signtool failed with exit code $LASTEXITCODE; the unsigned build was kept."
            }
        }
    }
}

Write-Host ""
Write-Host "Built: $DistDir"
Write-Host "Run:   $TargetExe"
New-Item -ItemType Directory -Path $ReleaseDir -Force | Out-Null
$Archive = Join-Path $ReleaseDir "AETHER-windows-v$Version.zip"
if (Test-Path $Archive) { Remove-Item $Archive -Force }
Compress-Archive -Path $DistDir -DestinationPath $Archive
Write-Host "Archive: $Archive"
