# GitOps Promoter Helm Chart

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
  name: my-helm-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/argoproj-labs/gitops-promoter-helm
    targetRevision: HEAD # Or a specific version/branch/tag
    path: chart # The path within the Git repo to the chart
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


## Updates

This project uses [Kubebuilder](https://github.com/kubernetes-sigs/kubebuilder) and the helm plugin to create/update the charts.
The helm chart will be automatically updated when new GitOps Promoter versions are released.

Please see:[kubebuilder helm plugin documentation](https://book.kubebuilder.io/plugins/available/helm-v2-alpha) for more information on how to update the chart.