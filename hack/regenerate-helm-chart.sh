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
#   --manifests  <promoter-repo>/dist/install-without-ui.yaml (requires gitops-promoter >= 0.32.0)
#
# Requires: kubebuilder on PATH (run hack/install-kubebuilder.sh first on CI).
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

# Controller-only manifests the chart is generated from. gitops-promoter >= 0.32.0 ships
# this as dist/install-without-ui.yaml (the dashboard apiserver ships separately and is
# helmified by hack/update-apiserver-templates.sh). Versions < 0.32.0 are not supported.
MANIFESTS="${MANIFESTS:-${GITOPS_PROMOTER_REPO}/dist/install-without-ui.yaml}"
if [[ ! -f "$MANIFESTS" ]]; then
  echo "Error: manifests file not found: $MANIFESTS" >&2
  echo "       gitops-promoter >= 0.32.0 is required (it ships dist/install-without-ui.yaml)." >&2
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
