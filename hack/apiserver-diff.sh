#!/usr/bin/env bash
#
# Fail if the committed dashboard apiserver templates do not match what
# hack/update-apiserver-templates.sh generates from the upstream config/apiserver/.
#
# This is the verifier half of the generator/verifier pair (the generator,
# update-apiserver-templates.sh, is what *resolves* drift). It mirrors the
# regenerate-helm-chart.sh <-> chart-diff.sh relationship.
#
# Usage:
#   hack/apiserver-diff.sh --gitops-promoter-repo /path/to/gitops-promoter \
#     [--helm-repo /path/to/gitops-promoter-helm] [--write-diff /path/to/apiserver-diff.diff]
#
# Requires: yq (mikefarah), perl.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HELM_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

GITOPS_PROMOTER_REPO=""
HELM_REPO="$DEFAULT_HELM_REPO"
WRITE_DIFF=""

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

if [[ -z "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Usage: $0 --gitops-promoter-repo DIR [--helm-repo DIR] [--write-diff FILE]" >&2
  exit 1
fi
if [[ ! -d "$GITOPS_PROMOTER_REPO" ]]; then
  echo "Error: --gitops-promoter-repo not a directory: $GITOPS_PROMOTER_REPO" >&2
  exit 1
fi

GITOPS_PROMOTER_REPO="$(cd "$GITOPS_PROMOTER_REPO" && pwd)"
HELM_REPO="$(cd "$HELM_REPO" && pwd)"
APISERVER_DIR="$HELM_REPO/chart/templates/extras/apiserver"

# If the pinned gitops-promoter version predates config/apiserver/ we cannot verify the
# committed templates against it. The chart may intentionally stage these templates ahead
# of the release that ships the apiserver (see the plan's sequencing note), so skip rather
# than fail; the strict check kicks in once gitops_promoter_version includes the apiserver.
if [[ ! -d "$GITOPS_PROMOTER_REPO/config/apiserver/base" ]]; then
  echo "Skipping: this gitops-promoter version has no config/apiserver/ to verify against."
  exit 0
fi

SNAPSHOT="$(mktemp -d)"
trap 'rm -rf "$SNAPSHOT"' EXIT

if [[ -d "$APISERVER_DIR" ]]; then
  cp -a "$APISERVER_DIR" "$SNAPSHOT/committed"
else
  mkdir -p "$SNAPSHOT/committed"
fi

echo "Regenerating apiserver templates to compare against committed copy..."
bash "$SCRIPT_DIR/update-apiserver-templates.sh" \
  --helm-repo "$HELM_REPO" \
  --gitops-promoter-repo "$GITOPS_PROMOTER_REPO" >/dev/null

DIFF_OUT="${WRITE_DIFF:-/tmp/apiserver-diff.diff}"
set +e
diff -ruN "$SNAPSHOT/committed" "$APISERVER_DIR" >"$DIFF_OUT"
DIFF_STATUS=$?
set -e

# Restore the committed copy so the worktree is left unchanged either way.
rm -rf "$APISERVER_DIR"
cp -a "$SNAPSHOT/committed" "$APISERVER_DIR"

if [[ "$DIFF_STATUS" -ne 0 && "$DIFF_STATUS" -ne 1 ]]; then
  echo "diff failed with exit code $DIFF_STATUS" >&2
  exit "$DIFF_STATUS"
fi

if [[ -s "$DIFF_OUT" ]]; then
  echo "=== Dashboard apiserver templates are stale (run hack/update-apiserver-templates.sh) ==="
  cat "$DIFF_OUT"
  exit 1
fi

echo "No differences found: committed apiserver templates match the generator."
rm -f "$DIFF_OUT"
exit 0
