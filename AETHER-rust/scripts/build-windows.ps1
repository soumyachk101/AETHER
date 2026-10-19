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

Write-Host "==> Building dibi-aether (release)"
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
dibi AETHER (Windows)
=====================

Run:
  .\AETHER.exe

The app starts the OpenDots Node server on 127.0.0.1:4310 and stops it on exit.
The web app must already be built (npm ci && npm run build in the OpenDots app
directory). If it lives elsewhere, set OPENDOTS_ROOT to its absolute path.

Requirements: Node.js 24+ in PATH and the built OpenDots dist/ output. The
native egui application does not require the WebView2 Runtime.

Environment overrides:
  OPENDOTS_ROOT   OpenDots project root (contains package.json and src\server\index.ts)
  AETHER_URL      Attach to an existing server instead of starting one
  AETHER_PORT     Port for the local server (default 4310; PORT also works)
  OWNER_TOKEN     Owner token forwarded to the server

Log:
  %LOCALAPPDATA%\dibi-aether\server.log

There is no installer; this folder is portable. Keep AETHER.exe alongside
any files you want to ship, or copy it anywhere and set OPENDOTS_ROOT.
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
