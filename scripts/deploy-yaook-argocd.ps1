param(
  [string]$RepoURL = "",
  [string]$TargetRevision = "HEAD",
  [switch]$InstallHarbor = $false,
  [switch]$ConfigureRepoSecret = $false,
  [string]$RepoUsername = "git",
  [string]$TokenEnvVar = "GITHUB_TOKEN",
  [string]$ArgoCDVersion = "stable"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-Kubectl {
  $script:KubectlCmd = $null
  $binDir = Join-Path (Split-Path $PSCommandPath -Parent) '..' | Join-Path -ChildPath 'bin'
  $kubectlLocal = Join-Path $binDir 'kubectl.exe'

  $kCmd = Get-Command kubectl -ErrorAction SilentlyContinue
  if ($kCmd -and $kCmd.Source) { $script:KubectlCmd = $kCmd.Source }
  elseif (Test-Path $kubectlLocal) { $script:KubectlCmd = $kubectlLocal }
  else { Write-Error "Required command 'kubectl' not found on PATH and local bin." }
}

function Invoke-K { & $script:KubectlCmd @args }

function Resolve-RepoURL {
  if ($RepoURL -and $RepoURL.Trim()) { return $RepoURL.Trim() }

  $gitCmd = Get-Command git -ErrorAction SilentlyContinue
  if ($gitCmd -and $gitCmd.Source) {
    $url = (& git config --get remote.origin.url) 2>$null
    if ($url -and $url.Trim()) { return $url.Trim() }
  }

  Write-Error "RepoURL is required. Pass -RepoURL or ensure git remote.origin.url is set."
}

Resolve-Kubectl
$RepoURL = Resolve-RepoURL

$repoRoot = Split-Path $PSCommandPath -Parent | Split-Path -Parent
$gitopsDir = Join-Path $repoRoot 'gitops'
$appsDir = Join-Path $gitopsDir 'apps'

Write-Host "Installing Argo CD ($ArgoCDVersion)..." -ForegroundColor Cyan
Invoke-K get ns argocd -o name 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) { Invoke-K create namespace argocd | Out-Null }

$installUrl = "https://raw.githubusercontent.com/argoproj/argo-cd/$ArgoCDVersion/manifests/install.yaml"
Invoke-K apply -n argocd -f $installUrl | Out-Null

Write-Host "Waiting for Argo CD to be ready..." -ForegroundColor Cyan
Invoke-K -n argocd rollout status deploy/argocd-server --timeout=300s | Out-Null
Invoke-K -n argocd rollout status deploy/argocd-repo-server --timeout=300s | Out-Null
try {
  Invoke-K -n argocd rollout status deploy/argocd-application-controller --timeout=300s | Out-Null
} catch {
  Invoke-K -n argocd rollout status statefulset/argocd-application-controller --timeout=300s | Out-Null
}

Write-Host "Applying AppProject..." -ForegroundColor Cyan
Invoke-K apply -f (Join-Path $gitopsDir 'app-project.yaml') | Out-Null

if ($ConfigureRepoSecret) {
  $token = [Environment]::GetEnvironmentVariable($TokenEnvVar)
  if (-not $token -or -not $token.Trim()) { Write-Error "Environment variable '$TokenEnvVar' must be set when -ConfigureRepoSecret is used." }

  $repoSecretYaml = @"
apiVersion: v1
kind: Secret
metadata:
  name: repo-yaook-gitops
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  url: $RepoURL
  username: $RepoUsername
  password: $token
"@

  $repoSecretYaml | & $script:KubectlCmd apply -f - | Out-Null
}

Write-Host "Applying Applications..." -ForegroundColor Cyan
$appFiles = Get-ChildItem -Path $appsDir -Filter '*.yaml' | Sort-Object Name
foreach ($f in $appFiles) {
  if (-not $InstallHarbor -and $f.Name -ieq 'harbor.yaml') { continue }

  if ($f.Name -ieq 'cert-issuers.yaml') {
    $content = Get-Content -Path $f.FullName -Raw
    $content = $content.Replace('__REPO_URL__', $RepoURL).Replace('__TARGET_REVISION__', $TargetRevision)
    $content | & $script:KubectlCmd apply -f - | Out-Null
    continue
  }

  Invoke-K apply -f $f.FullName | Out-Null
}

Write-Host "Done. Check Argo CD Applications in namespace 'argocd'." -ForegroundColor Green
