#!/usr/bin/env bash
#
# Run kubebuilder helm/v2-alpha against a gitops-promoter clone and write the chart
# into the gitops-promoter-helm repo, then apply post-kubebuilder fixes.
#
# Usage (from anywhere):
#   hack/regenerate-helm-chart.sh --gitops-promoter-repo /path/to/gitops-promoter \
#     [--helm-repo /path/to/gitops-promoter-helm] [--manifests /path/to/install.yaml]
#
# Defaults:
#   --helm-repo  parent of hack/ (this repository root)
#   --manifests  controller-only manifests: <promoter-repo>/dist/install-without-ui.yaml
#                (gitops-promoter 0.32.0 - 0.48.x), else derived from
#                <promoter-repo>/dist/install-with-dashboard.yaml (>= 0.49.0)
#
# Requires: kubebuilder on PATH (run hack/install-kubebuilder.sh first on CI); yq
# (mikefarah) for gitops-promoter >= 0.49.0.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HELM_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

GITOPS_PROMOTER_REPO=""
HELM_REPO="$DEFAULT_HELM_REPO"
MANIFESTS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitops-promoter-repo)
      GITOPS_PROMOTER_REPO="${2:?}"
      shift 2
      ;;
    --helm-repo)
      HELM_REPO="${2:?}"
      shift 2
      ;;
    --manifests)
      MANIFESTS="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Error: --gitops-promoter-repo is required." >&2
  exit 1
fi

if [[ ! -d "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Error: --gitops-promoter-repo not a directory: $GITOPS_PROMOTER_REPO" >&2
  exit 1
fi
if [[ ! -d "$HELM_REPO" ]]; then
  echo "Error: --helm-repo not a directory: $HELM_REPO" >&2
  exit 1
fi

GITOPS_PROMOTER_REPO="$(cd "$GITOPS_PROMOTER_REPO" && pwd)"
HELM_REPO="$(cd "$HELM_REPO" && pwd)"
CHART_DIR="${HELM_REPO}/chart"

# The chart is generated from controller-only manifests. The dashboard apiserver is
# helmified separately by hack/update-apiserver-templates.sh (cert-mode aware), so it must
# not reach kubebuilder.
#   - gitops-promoter 0.32.0 - 0.48.x ship dist/install-without-ui.yaml: use it as-is.
#   - gitops-promoter >= 0.49.0 only ship bundles that include the apiserver. Derive the
#     controller-only manifests from dist/install-with-dashboard.yaml.
# Versions < 0.32.0 are not supported.
if [[ -z "$MANIFESTS" ]]; then
  if [[ -f "${GITOPS_PROMOTER_REPO}/dist/install-without-ui.yaml" ]]; then
    MANIFESTS="${GITOPS_PROMOTER_REPO}/dist/install-without-ui.yaml"
  elif [[ -f "${GITOPS_PROMOTER_REPO}/dist/install-with-dashboard.yaml" ]]; then
    if ! command -v yq >/dev/null 2>&1; then
      echo "Error: yq (https://github.com/mikefarah/yq) is required." >&2
      exit 1
    fi
    FILTER_DIR="$(mktemp -d)"
    trap 'rm -rf "$FILTER_DIR"' EXIT
    MANIFESTS="${FILTER_DIR}/install-controller-only.yaml"
    # Drop every dashboard apiserver resource (upstream labels them all
    # app.kubernetes.io/component: dashboard-apiserver) and the controller's
    # --apiserver-cert-rotation* flags; the chart adds those back per apiserver.certs.mode.
    yq '
      select(.metadata.labels."app.kubernetes.io/component" != "dashboard-apiserver") |
      (select(.kind == "Deployment") | .spec.template.spec.containers[].args) |=
        ((. // []) | map(select(test("^--apiserver-cert-rotation") | not)))
    ' "${GITOPS_PROMOTER_REPO}/dist/install-with-dashboard.yaml" >"$MANIFESTS"
    # Fail loudly if upstream stops labelling something, rather than silently helmifying
    # apiserver resources into the kubebuilder-owned templates.
    if leftovers="$(yq -N 'select(.kind == "APIService" or (.metadata.name | test("apiserver"))) | .kind + "/" + .metadata.name' "$MANIFESTS")" && [[ -n "$leftovers" ]]; then
      echo "Error: dashboard apiserver resources left after filtering install-with-dashboard.yaml:" >&2
      echo "$leftovers" >&2
      echo "       Update the filter in $0." >&2
      exit 1
    fi
    if grep -q -- '--apiserver-' "$MANIFESTS"; then
      echo "Error: --apiserver-* controller flags left after filtering install-with-dashboard.yaml." >&2
      exit 1
    fi
  else
    echo "Error: neither dist/install-without-ui.yaml nor dist/install-with-dashboard.yaml found in $GITOPS_PROMOTER_REPO" >&2
    echo "       gitops-promoter >= 0.32.0 is required." >&2
    exit 1
  fi
fi
if [[ ! -f "$MANIFESTS" ]]; then
  echo "Error: manifests file not found: $MANIFESTS" >&2
  exit 1
fi

if ! command -v kubebuilder >/dev/null 2>&1; then
  echo "Error: kubebuilder not on PATH. Install with: KUBEBUILDER_VERSION=... hack/install-kubebuilder.sh" >&2
  exit 1
fi

echo "Running kubebuilder edit (helm/v2-alpha)..."
echo "  promoter:  $GITOPS_PROMOTER_REPO"
echo "  output:    $HELM_REPO"
echo "  manifests: $MANIFESTS"
(
  cd "$GITOPS_PROMOTER_REPO"
  kubebuilder edit --plugins=helm/v2-alpha --output-dir="$HELM_REPO" --manifests="$MANIFESTS"
)

bash "$SCRIPT_DIR/apply-post-kubebuilder-chart-fixes.sh" "$CHART_DIR"
echo "Regenerated chart at: $CHART_DIR"
