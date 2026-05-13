#!/usr/bin/env bash
#
# Fail if the committed chart does not match kubebuilder regeneration + post-fixes.
# Same logic as the chart-diff GitHub Actions workflow.
#
# Usage:
#   hack/chart-diff.sh --helm-repo /path/to/gitops-promoter-helm \
#     --gitops-promoter-repo /path/to/gitops-promoter \
#     [--write-diff /path/to/chart-diff.diff]
#
# Environment:
#   KUBEBUILDER_VERSION  (optional; passed to install-kubebuilder.sh)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_REPO=""
GITOPS_PROMOTER_REPO=""
WRITE_DIFF=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helm-repo)
      HELM_REPO="${2:?}"
      shift 2
      ;;
    --gitops-promoter-repo)
      GITOPS_PROMOTER_REPO="${2:?}"
      shift 2
      ;;
    --write-diff)
      WRITE_DIFF="${2:?}"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$HELM_REPO" || -z "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Usage: $0 --helm-repo DIR --gitops-promoter-repo DIR [--write-diff FILE]" >&2
  exit 1
fi

if [[ ! -d "$HELM_REPO" ]]; then
  echo "Error: --helm-repo not a directory: $HELM_REPO" >&2
  exit 1
fi
if [[ ! -d "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Error: --gitops-promoter-repo not a directory: $GITOPS_PROMOTER_REPO" >&2
  exit 1
fi

HELM_REPO="$(cd "$HELM_REPO" && pwd)"
GITOPS_PROMOTER_REPO="$(cd "$GITOPS_PROMOTER_REPO" && pwd)"
CHART_DIR="${HELM_REPO}/chart"

if [[ ! -d "$CHART_DIR" ]]; then
  echo "Error: chart directory not found: $CHART_DIR" >&2
  exit 1
fi

SNAPSHOT="$(mktemp -d)"
trap 'rm -rf "$SNAPSHOT"' EXIT

echo "Saving chart snapshot to $SNAPSHOT/chart ..."
cp -a "$CHART_DIR" "$SNAPSHOT/chart"

export INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
bash "$SCRIPT_DIR/install-kubebuilder.sh"
export PATH="$INSTALL_DIR:$PATH"

bash "$SCRIPT_DIR/regenerate-helm-chart.sh" \
  --helm-repo "$HELM_REPO" \
  --gitops-promoter-repo "$GITOPS_PROMOTER_REPO"

# kubebuilder may rewrite templates/extras/ even though chart-diff excludes it from
# comparison — restore chart-owned extras from the snapshot so the worktree stays clean.
if [[ -d "$SNAPSHOT/chart/templates/extras" ]]; then
  rm -rf "$CHART_DIR/templates/extras"
  cp -a "$SNAPSHOT/chart/templates/extras" "$CHART_DIR/templates/"
fi

DIFF_OUT="${WRITE_DIFF:-/tmp/chart-diff.diff}"
echo "=== Diff between committed chart and regenerated chart ==="
set +e
diff -ruN \
  --exclude='.git' \
  --exclude='*.orig' \
  --exclude='extra' \
  --exclude='extras' \
  "$SNAPSHOT/chart" \
  "$CHART_DIR" >"$DIFF_OUT"
DIFF_STATUS=$?
set -e

if [[ "$DIFF_STATUS" -ne 0 && "$DIFF_STATUS" -ne 1 ]]; then
  echo "diff failed with exit code $DIFF_STATUS" >&2
  exit "$DIFF_STATUS"
fi

if [[ -s "$DIFF_OUT" ]]; then
  echo "Differences found:"
  cat -n "$DIFF_OUT"
  exit 1
fi

echo "No differences found."
rm -f "$DIFF_OUT"
exit 0
