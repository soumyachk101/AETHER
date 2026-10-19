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

Set-Location $ProjectDir

if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    throw "cargo was not found in PATH. Install Rust 1.85+ from https://rustup.rs."
}

Write-Host "==> Building AETHER (native Rust release executable)"
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

$Readme = @'
AETHER (native Windows desktop bundle)
======================================

Run:
  .\AETHER.exe

This bundle contains the native Rust desktop executable, not a web app or
Node.js runtime. It starts the OpenDots Node server on 127.0.0.1:4310 and
stops it on exit. Build OpenDots first (npm ci && npm run build in AETHER-web/).
The app root must include node_modules/ and dist/server/server/index.js. If it
is not discoverable beside this bundle, set OPENDOTS_ROOT to its absolute path.

Runtime requirements: Microsoft Edge WebView2 Evergreen Runtime, Node.js 24+
in PATH, and the built OpenDots app with node_modules/. The build machine needs
Rust 1.85+ with the MSVC toolchain and Visual Studio Build Tools with the C++
workload. See AETHER-rust/README.md for details.

Environment overrides:
  OPENDOTS_ROOT   OpenDots root (package.json, node_modules\, and dist\server\server\index.js)
  AETHER_URL      Attach to an existing server instead of starting one
  AETHER_PORT     Port for the local server (default 4310; PORT also works)
  OWNER_TOKEN     Owner token forwarded to the server

Log:
  %LOCALAPPDATA%\dibi-aether\server.log

There is no installer; this folder is portable. Output: dist\windows\AETHER.exe
and this README.txt. Keep the built OpenDots app and its node_modules available
and set OPENDOTS_ROOT if the app root cannot be auto-detected.
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
