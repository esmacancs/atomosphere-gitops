<#
Purpose: Deploy YAOOK operators on Kubernetes WITHOUT Ceph (demo-only)
Platform: Windows PowerShell

Prereqs:
- A reachable Kubernetes cluster
- kubectl and helm installed and on PATH

What this script does:
- Creates namespace for Yaook
- Installs a default StorageClass (local-path-provisioner)
- Installs cert-manager and sets up a self-signed CA in the Yaook namespace
- Installs Prometheus stack and NGINX ingress via Helm
- Installs Yaook CRDs and selected operators (no glance, no cinder)
- Labels all nodes with generic "any" labels for demo scheduling

Note:
- This is NOT for production use
- For images and block storage, add Glance (file/PVC) or deploy Ceph/another CSI
#>

param(
  [string]$Namespace = "yaook",
  [string]$LocalPathProvisionerVersion = "v0.0.31",
  [string]$CertManagerVersion = "v1.13.3",
  [switch]$InstallGlance = $false,
  [switch]$InstallCinder = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Command($name) {
  if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
    Write-Error "Required command '$name' not found on PATH. Please install it and retry."
  }
}

Write-Host "Checking required commands..." -ForegroundColor Cyan
function Resolve-ToolPaths {
  $script:KubectlCmd = $null
  $script:HelmCmd = $null
  $binDir = Join-Path (Split-Path $PSCommandPath -Parent) '..' | Join-Path -ChildPath 'bin'
  $kubectlLocal = Join-Path $binDir 'kubectl.exe'
  $helmLocal = Join-Path $binDir 'helm.exe'

  $kCmd = Get-Command kubectl -ErrorAction SilentlyContinue
  if ($kCmd -and $kCmd.Source) { $script:KubectlCmd = $kCmd.Source }
  elseif (Test-Path $kubectlLocal) { $script:KubectlCmd = $kubectlLocal }
  else { Write-Error "Required command 'kubectl' not found on PATH and local bin." }

  $hCmd = Get-Command helm -ErrorAction SilentlyContinue
  if ($hCmd -and $hCmd.Source) { $script:HelmCmd = $hCmd.Source }
  elseif (Test-Path $helmLocal) { $script:HelmCmd = $helmLocal }
  else { Write-Error "Required command 'helm' not found on PATH and local bin." }
}

function Invoke-Helm { & $script:HelmCmd @args }
function Invoke-K { & $script:KubectlCmd @args }

Resolve-ToolPaths

Write-Host "Creating namespace '$Namespace' (idempotent)..." -ForegroundColor Cyan
Invoke-K get ns $Namespace -o name 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Invoke-K create namespace $Namespace | Out-Null }

Write-Host "Installing local-path-provisioner $LocalPathProvisionerVersion..." -ForegroundColor Cyan
Invoke-K apply -f "https://raw.githubusercontent.com/rancher/local-path-provisioner/$LocalPathProvisionerVersion/deploy/local-path-storage.yaml" | Out-Null
Start-Sleep -Seconds 2
try { Invoke-K annotate storageclass local-path storageclass.kubernetes.io/is-default-class=true --overwrite | Out-Null } catch {}

Write-Host "Installing cert-manager $CertManagerVersion..." -ForegroundColor Cyan
Invoke-K apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CertManagerVersion/cert-manager.crds.yaml" | Out-Null
Invoke-K apply -f "https://github.com/cert-manager/cert-manager/releases/download/$CertManagerVersion/cert-manager.yaml" | Out-Null
Write-Host "Waiting for cert-manager webhook to be ready..." -ForegroundColor Cyan
Invoke-K -n cert-manager rollout status deploy/cert-manager-webhook --timeout=180s | Out-Null

Write-Host "Setting up self-signed CA and Issuer in namespace '$Namespace'..." -ForegroundColor Cyan
Invoke-K apply -n $Namespace -f "$(Join-Path (Split-Path $PSCommandPath -Parent) '..\manifests\cert-manager-issuers.yaml')" | Out-Null

Write-Host "Installing monitoring and ingress via Helm (demo defaults)..." -ForegroundColor Cyan
Invoke-Helm repo add prometheus-community https://prometheus-community.github.io/helm-charts | Out-Null
Invoke-Helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack -n monitoring --create-namespace | Out-Null
Invoke-Helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx | Out-Null
Invoke-Helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace | Out-Null

Write-Host "Adding Yaook Helm repos..." -ForegroundColor Cyan
Invoke-Helm repo add stable https://charts.helm.sh/stable | Out-Null
Invoke-Helm repo add yaook.cloud https://charts.yaook.cloud/operator/stable/ | Out-Null
Invoke-Helm repo update | Out-Null

Write-Host "Selecting Yaook chart version..." -ForegroundColor Cyan
$search = Invoke-Helm search repo yaook.cloud/crds -o json | ConvertFrom-Json
if (-not $search -or $search.Count -lt 1) { Write-Error "Could not find yaook.cloud/crds in Helm repos." }
$YAOOK_VERSION = $search[0].version
Write-Host "Using YAOOK_VERSION=$YAOOK_VERSION" -ForegroundColor Green

Write-Host "Installing Yaook CRDs..." -ForegroundColor Cyan
Invoke-Helm upgrade --install -n $Namespace --version $YAOOK_VERSION crds yaook.cloud/crds | Out-Null

$operators = @("infra","keystone","keystone-resources","nova","nova-compute","neutron","neutron-ovn","horizon")
if ($InstallGlance) { $operators += "glance" }
if ($InstallCinder) { $operators += "cinder" }

Write-Host "Deploying selected Yaook operators: $($operators -join ', ')" -ForegroundColor Cyan
foreach ($op in $operators) {
  $releaseName = "$op-operator"
  $chart = "yaook.cloud/$op-operator"
  Write-Host "Installing $chart (release $releaseName)..." -ForegroundColor DarkCyan
  Invoke-Helm upgrade --install -n $Namespace --version $YAOOK_VERSION $releaseName $chart | Out-Null
}

Write-Host "Labeling all nodes with demo 'any' labels for scheduling..." -ForegroundColor Cyan
$labels = @(
  "infra.yaook.cloud/any=true",
  "operator.yaook.cloud/any=true",
  "compute.yaook.cloud/nova-any-service=true",
  "network.yaook.cloud/neutron-northd=true",
  "network.yaook.cloud/neutron-ovn-agent=true"
)
$nodes = Invoke-K get nodes -o name
$nodes = $nodes -split "`n" | ForEach-Object { $_ -replace '^node/', '' } | Where-Object { $_ -ne '' }
foreach ($n in $nodes) {
  foreach ($l in $labels) {
    Invoke-K label node $n $l --overwrite | Out-Null
  }
}

Write-Host "Deployment triggered. Current pods in '$Namespace':" -ForegroundColor Cyan
Invoke-K -n $Namespace get pods

Write-Host "Done. Note: Glance and Cinder are omitted unless explicitly enabled." -ForegroundColor Yellow