# GitOps Promoter Helm Chart

[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/gitops-promoter-helm)](https://artifacthub.io/packages/helm/gitops-promoter/gitops-promoter)

GitOps Promoter is a Kubernetes controller for automating GitOps-based application promotion across environments.

Source code can be found here:
- https://github.com/argoproj-labs/gitops-promoter-helm
- https://github.com/argoproj-labs/gitops-promoter

This is the official Helm chart for the GitOps Promoter project.

## Installation

Unfortunately, some technical choices from [kubebuilder](https://book.kubebuilder.io/plugins/available/helm-v2-alpha#chart-structure) prevent us from providing installing with `helm install`.
We approve the choice made, and we might provide a better solution once the feature for [creation sequencing](https://helm.sh/community/hips/hip-0025/) is implemented.


We recommend to install the chart using Argo CD:
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitops-promoter
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://argoproj-labs.github.io/gitops-promoter-helm/
    chart: gitops-promoter
    targetRevision: "*" # Or a specific version
  destination:
    server: "https://kubernetes.default.svc"
    namespace: promoter-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
```

Or you can install the chart using `kubectl`:
```
helm repo add gitops-promoter-helm https://argoproj-labs.github.io/gitops-promoter-helm/
helm repo update
# Initial apply to install CRDs. It's expected to fail, since we install the ControllerConfiguration CRD and a ControllerConfiguration CR in the same apply.
kubectl create namespace promoter-system
helm template  gitops-promoter-helm/gitops-promoter --namespace promoter-system | kubectl apply -f - || true 
helm template  gitops-promoter-helm/gitops-promoter --namespace promoter-system | kubectl apply -f -
```


## Dashboard aggregation API server

The chart can optionally deploy the GitOps Promoter **dashboard aggregation API server**, an
extension API server that serves the read-only `view.promoter.argoproj.io/v1alpha1`
`PromotionStrategyDetails` API through the Kubernetes aggregation layer (it backs the
GitOps Promoter UI). It is **disabled by default** and requires a GitOps Promoter version
that ships the `apiserver` subcommand.

Enable it with:

```yaml
apiserver:
  enabled: true
  certs:
    mode: insecure   # insecure | cert-manager | manual
```

### Serving-certificate modes

The aggregation layer requires the API server to serve TLS, and the `APIService` needs the
matching CA (or to skip verification). Pick one of three modes via `apiserver.certs.mode`:

- **`insecure`** (default): the API server self-signs its serving certificate in-pod and the
  `APIService` is registered with `insecureSkipTLSVerify: true`. No `Secret` is rendered, so
  there is nothing for Argo CD to churn on. **This is not production-safe** — the aggregator
  does not verify the API server's certificate. Use `cert-manager` for production.
- **`cert-manager`**: a self-signed cert-manager `Issuer` + `Certificate` issue the serving
  certificate, and cert-manager's CA injector keeps the `APIService` `caBundle` in sync
  (including on rotation). Requires cert-manager in the cluster. Point at an existing issuer
  with `apiserver.certs.certManager.issuer.{create,name,kind}`.
- **`manual`**: you provide the serving-certificate `Secret`
  (`apiserver.certs.secretName`, default `promoter-apiserver-serving-cert`) out-of-band and
  set `apiserver.certs.caBundle` (base64-encoded PEM) so it is written to the `APIService`.

Verify the install with:

```bash
kubectl get apiservice v1alpha1.view.promoter.argoproj.io   # should report Available=True
kubectl get promotionstrategydetails -A
```

See the upstream [Dashboard aggregation API docs](https://github.com/argoproj-labs/gitops-promoter/blob/main/docs/advanced-usage/dashboard-apiserver.md) for details.

## Known Limitations

### kube-rbac-proxy image and resources are not configurable

The chart currently deploys a `kube-rbac-proxy` sidecar container whose image and resource requests/limits cannot be overridden via `values.yaml`.
This is a limitation inherited from how [kubebuilder](https://book.kubebuilder.io/plugins/available/helm-v2-alpha) generates the Helm chart.

Tracking issue for removing `kube-rbac-proxy` from the upstream project: https://github.com/argoproj-labs/gitops-promoter/issues/1085

## Updates

This project uses [Kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) and the helm plugin to create/update the charts.
The helm chart will be automatically updated when new GitOps Promoter versions are released.

Please see:[kubebuilder helm plugin documentation](https://book.kubebuilder.io/plugins/available/helm-v2-alpha) for more information on how to update the chart.

## Verifying the chart signature

```bash
# Public key is at https://argoproj-labs.github.io/gitops-promoter-helm/pgp_keys.asc
helm repo add gitops-promoter https://argoproj-labs.github.io/gitops-promoter-helm/
helm repo update
helm verify gitops-promoter/gitops-promoter  # verify before install
```
