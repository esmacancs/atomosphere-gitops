# Argo CD GitOps for Yaook (No-Ceph Demo)

This directory contains Argo CD resources to deploy Yaook operators (without Ceph) and common dependencies via GitOps.

## Contents
- `app-project.yaml`: Argo CD AppProject allowing deployments to required namespaces
- `apps/`: Application manifests for:
  - `local-path-provisioner` (StorageClass)
  - `cert-manager` and `yaook-cert-issuers` (CA/Issuer in Yaook ns)
  - `ingress-nginx`
  - `kube-prometheus-stack`
  - `yaook-crds` and all Yaook operator charts
  - `harbor` (optional in-cluster registry)

## Prerequisites
- Argo CD installed (`argocd` namespace)
- Kubernetes cluster accessible by Argo CD

## Usage
1. Commit and push this repo to a Git remote accessible by Argo CD.
2. Apply the project and applications:
   - `kubectl apply -n argocd -f gitops/app-project.yaml`
   - `kubectl apply -n argocd -f gitops/apps/`
3. Patch `gitops/apps/cert-issuers.yaml` placeholders (`__REPO_URL__`, `__TARGET_REVISION__`) to match your Git remote.
4. Argo CD will sync apps in waves:
   - Wave 0: local-path-provisioner
   - Wave 1: cert-manager, ingress-nginx, kube-prometheus-stack (and harbor if enabled)
   - Wave 2: cert issuers in Yaook ns
   - Wave 3: Yaook CRDs
   - Wave 4: Yaook operators (infra, keystone, nova, neutron, horizon)

## Notes
- Glance and Cinder are intentionally omitted (no Ceph). Add them only if you configure a suitable storage backend.
- The Yaook chart versions are pinned; update `targetRevision` as needed.
- Ensure `local-path-provisioner` becomes the default `StorageClass` or define a default in your cluster.
