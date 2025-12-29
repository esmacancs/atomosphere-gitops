<#
Purpose: Download portable kubectl and helm binaries into local ./bin for Windows
This avoids system-wide install requirements.
#>

param(
  [string]$HelmVersion = "v3.14.4"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$binDir = Join-Path $repoRoot 'bin'
if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Path $binDir | Out-Null }

Write-Host "Fetching latest kubectl stable version..." -ForegroundColor Cyan
$stableVersion = (Invoke-RestMethod -Uri "https://dl.k8s.io/release/stable.txt").Trim()
if (-not $stableVersion) { Write-Error "Unable to determine kubectl stable version." }

$kubectlUrl = "https://dl.k8s.io/release/$stableVersion/bin/windows/amd64/kubectl.exe"
$kubectlPath = Join-Path $binDir 'kubectl.exe'
Write-Host "Downloading kubectl $stableVersion..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $kubectlUrl -OutFile $kubectlPath

Write-Host "Downloading helm $HelmVersion..." -ForegroundColor Cyan
$helmZipUrl = "https://get.helm.sh/helm-$HelmVersion-windows-amd64.zip"
$zipPath = Join-Path $binDir "helm-$HelmVersion-windows-amd64.zip"
Invoke-WebRequest -Uri $helmZipUrl -OutFile $zipPath
Expand-Archive -Path $zipPath -DestinationPath $binDir -Force
Remove-Item $zipPath -Force

$helmExe = Join-Path $binDir 'windows-amd64' | Join-Path -ChildPath 'helm.exe'
if (Test-Path $helmExe) {
  Move-Item -Force $helmExe (Join-Path $binDir 'helm.exe')
  Remove-Item -Recurse -Force (Join-Path $binDir 'windows-amd64')
}

Write-Host "kubectl -> $kubectlPath" -ForegroundColor Green
Write-Host "helm    -> $(Join-Path $binDir 'helm.exe')" -ForegroundColor Green
Write-Host "Done. The deploy script will use local ./bin tools if PATH tools are missing." -ForegroundColor Yellow