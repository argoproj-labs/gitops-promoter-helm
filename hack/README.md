# Hack scripts

## update-artifacthub-crd-annotations.sh

Updates `chart/Chart.yaml` with [Artifact Hub](https://artifacthub.io/docs/topics/annotations/helm/) annotations for CRDs and example CRs:

- **artifacthub.io/crds** – list of CRDs (kind, version, name, displayName, description) derived from the chart’s rendered CRD templates.
- **artifacthub.io/crdsExamples** – example Custom Resources loaded from the GitOps Promoter repo’s `internal/controller/testdata` directory.

Used by the **Update GitOps Promoter Version** workflow so that when the chart is updated from the gitops-promoter repo, these annotations are kept in sync.

### Local testing

From the **gitops-promoter-helm** repo root, pass the path to your local clone of **gitops-promoter** (must contain `internal/controller/testdata`):

```bash
bash hack/update-artifacthub-crd-annotations.sh --gitops-promoter-repo /path/to/gitops-promoter
```

**Requirements:** `helm` (for templating CRDs) and `yq` (https://github.com/mikefarah/yq). GitHub Ubuntu runners have `yq` available.
