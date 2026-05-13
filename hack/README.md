# Hack scripts

## Chart regeneration and CI parity

These scripts mirror what GitHub Actions does so you can reproduce chart updates locally.

| Script | Purpose |
|--------|---------|
| [`install-kubebuilder.sh`](install-kubebuilder.sh) | Download the pinned `kubebuilder` CLI (`KUBEBUILDER_VERSION`, default `v4.14.0`) into `/usr/local/bin` or `--install-dir`. Uses `sudo` when the directory is not writable. |
| [`regenerate-helm-chart.sh`](regenerate-helm-chart.sh) | Run `kubebuilder edit --plugins=helm/v2-alpha` from a **gitops-promoter** clone into this repo’s `chart/`, then run post-fixes. Requires `kubebuilder` on `PATH`. |
| [`apply-post-kubebuilder-chart-fixes.sh`](apply-post-kubebuilder-chart-fixes.sh) | Apply the same `sed` post-processing as CI (ArgoCDCommitStatus CRD escapes + Prometheus ServiceMonitor label). Takes a single argument: path to the **chart** directory. |
| [`chart-diff.sh`](chart-diff.sh) | Snapshot `chart/`, install kubebuilder, regenerate, then `diff` against the snapshot (excluding `templates/extra/` and `templates/extras/`). Exits non-zero if the committed chart does not match regen + fixes. |

### Local chart diff (same as PR `chart-diff` workflow)

From this repo root, with a clone of **gitops-promoter** at the tag matching `gitops_promoter_version`:

```bash
export KUBEBUILDER_VERSION=v4.14.0   # optional; must match CI
bash hack/chart-diff.sh \
  --helm-repo "$(pwd)" \
  --gitops-promoter-repo /path/to/gitops-promoter \
  --write-diff /tmp/chart-diff.diff
```

### Local regenerate only

After installing kubebuilder (or using one already on `PATH`):

```bash
bash hack/regenerate-helm-chart.sh \
  --helm-repo "$(pwd)" \
  --gitops-promoter-repo /path/to/gitops-promoter
```

Then run `helm lint chart` and review `git diff`.

---

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
