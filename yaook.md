# Yaook Operator (No-Ceph Demo) Deployment

This repository contains a Windows-friendly script to deploy the Yaook OpenStack operators on a Kubernetes cluster WITHOUT Ceph. This is suitable for quick demos; it is not recommended for production.

## Prerequisites
- A reachable Kubernetes cluster (Kubernetes API accessible from your machine)
- `kubectl` and `helm` installed and on PATH
- Sufficient cluster resources and a default StorageClass

## What gets installed
- Namespace `yaook` (configurable)
- `local-path-provisioner` default `StorageClass`
- `cert-manager` and a self-signed CA/Issuer in the Yaook namespace
- Monitoring (`kube-prometheus-stack`) and NGINX ingress
- Yaook CRDs and operators: `infra`, `keystone`, `keystone-resources`, `nova`, `nova-compute`, `neutron`, `neutron-ovn`, `horizon`
- Node labels applied to all nodes for demo scheduling

Glance and Cinder are omitted by default (no Ceph). You can enable them via script switches if you have alternative storage backends or PVC configuration for Glance.

## Deploy

Run the PowerShell script from the repository root:

```
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-yaook-no-ceph.ps1
```

Optional parameters:
- `-Namespace <name>`: change the deployment namespace (default: `yaook`)
- `-InstallGlance`: include `glance` operator (requires file/PVC store configuration)
- `-InstallCinder`: include `cinder` operator (requires a block storage backend)

Example:

```
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-yaook-no-ceph.ps1 -Namespace yaook -InstallGlance
```

## Deploy via Argo CD (GitOps)

If you recreated the cluster and want a GitOps-style deployment, install Argo CD and apply the Applications:

```
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-yaook-argocd.ps1 -RepoURL <your-git-repo-url>
```

If your Git repository is private, set an environment variable with a Git token and let the script configure Argo CD repo credentials:

```
$env:GITHUB_TOKEN = "<token>"
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-yaook-argocd.ps1 -RepoURL <your-git-repo-url> -ConfigureRepoSecret
```

To also install an in-cluster Harbor registry (NodePorts 30080/30443):

```
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\scripts\deploy-yaook-argocd.ps1 -RepoURL <your-git-repo-url> -InstallHarbor
```

## Cert setup
The script installs cert-manager and applies `manifests/cert-manager-issuers.yaml` which:
- Creates a cluster-wide self-signed issuer
- Issues a CA certificate as secret `root-ca` in your Yaook namespace
- Creates an `Issuer` (`yaook-ca-issuer`) backed by that CA

This mirrors the quickstart’s `root-ca` setup without requiring `openssl`.

## Notes and Caveats
- Demo-only: expect limitations without Ceph (no robust block storage, images need PVC-backed Glance).
- Node labels: the script applies generic `any` labels to all nodes for convenience; for multi-node clusters, refine labels to separate control-plane and compute roles.
- If you enable Glance: configure Glance for file/PVC backend; RBD requires Ceph.
- If you enable Cinder: ensure a block storage CSI (e.g., Ceph, Longhorn, OpenEBS) is installed.

## Uninstall
You can remove the Helm releases and namespace:

```
helm -n yaook uninstall crds infra-operator keystone-operator keystone-resources-operator nova-operator nova-compute-operator neutron-operator neutron-ovn-operator horizon-operator
kubectl delete ns yaook
```

Also uninstall `kube-prometheus-stack`, `ingress-nginx`, and `local-path-provisioner` if they were installed solely for this demo.
