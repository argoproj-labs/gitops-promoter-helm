#!/usr/bin/env bash
#
# Update chart/values.yaml controllerConfiguration from the GitOps Promoter
# upstream config (config/config/controllerconfiguration.yaml). The kubebuilder
# helm plugin does not emit this resource; we copy the spec into values.yaml
# under controllerConfiguration and render it via templates/extra/controllerconfiguration.yaml.
#
# Usage:
#   ./hack/update-controllerconfiguration.sh --gitops-promoter-repo /path/to/gitops-promoter
#
# Run from the repo root (or from current-repo in CI). The chart is expected at chart/.
# Requires: yq (https://github.com/mikefarah/yq)
#
# The controllerConfiguration subtree is built with yq (load + assignment). The splice
# between # BEGIN / # END markers still uses awk so we do not run yq -i on all of
# values.yaml, which would reformat the entire file.

set -euo pipefail

BEGIN_MARKER="# BEGIN controllerConfiguration"
END_MARKER="# END controllerConfiguration"

GITOPS_PROMOTER_REPO=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitops-promoter-repo)
      GITOPS_PROMOTER_REPO="${2:?--gitops-promoter-repo requires a path}"
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

REPO_ROOT="$(pwd)"
CHART_DIR="$REPO_ROOT/chart"
VALUES_PATH="$CHART_DIR/values.yaml"
UPSTREAM_SOURCE="$GITOPS_PROMOTER_REPO/config/config/controllerconfiguration.yaml"

if [[ ! -d "$CHART_DIR" ]]; then
  echo "Error: chart dir not found: $CHART_DIR" >&2
  exit 1
fi
if [[ ! -f "$UPSTREAM_SOURCE" ]]; then
  echo "Error: upstream controllerconfiguration not found: $UPSTREAM_SOURCE" >&2
  exit 1
fi
if [[ ! -f "$VALUES_PATH" ]]; then
  echo "Error: values.yaml not found: $VALUES_PATH" >&2
  exit 1
fi

begin_n="$(tr -d '\r' <"$VALUES_PATH" | grep -cFx "$BEGIN_MARKER" || echo 0)"
end_n="$(tr -d '\r' <"$VALUES_PATH" | grep -cFx "$END_MARKER" || echo 0)"
if [[ "$begin_n" != 1 || "$end_n" != 1 ]]; then
  echo "Error: expected exactly one $BEGIN_MARKER and one $END_MARKER in $VALUES_PATH" >&2
  exit 1
fi

SPEC_TMP="$(mktemp "${TMPDIR:-/tmp}/controllerconfiguration-spec.XXXXXX.yaml")"
BLOCK_FILE="$(mktemp "${TMPDIR:-/tmp}/controllerconfiguration-block.XXXXXX")"
OUT_FILE="$(mktemp "${TMPDIR:-/tmp}/values-updated.XXXXXX")"
trap 'rm -f "$SPEC_TMP" "$BLOCK_FILE" "$OUT_FILE"' EXIT

yq '.spec' "$UPSTREAM_SOURCE" -o=yaml >"$SPEC_TMP"
SPEC_ABS="$(cd "$(dirname "$SPEC_TMP")" && pwd)/$(basename "$SPEC_TMP")"
export SPEC_ABS

{
  printf '%s\n' "$BEGIN_MARKER"
  echo "# Synced from upstream gitops-promoter config/config/controllerconfiguration.yaml"
  echo "# (do not edit manually; run hack/update-controllerconfiguration.sh)"
  yq -n '.controllerConfiguration = load(env(SPEC_ABS))' -o=yaml
  printf '%s\n' "$END_MARKER"
} >"$BLOCK_FILE"

awk -v blockfile="$BLOCK_FILE" -v begin="$BEGIN_MARKER" -v end="$END_MARKER" '
  {
    raw = $0
    sub(/\r$/, "", raw)
  }
  raw == begin {
    while ((getline line < blockfile) > 0) {
      print line
    }
    close(blockfile)
    in_block = 1
    next
  }
  in_block && raw == end {
    in_block = 0
    next
  }
  in_block {
    next
  }
  { print }
' "$VALUES_PATH" >"$OUT_FILE"

mv "$OUT_FILE" "$VALUES_PATH"
trap - EXIT
rm -f "$SPEC_TMP" "$BLOCK_FILE"

echo "Updated $VALUES_PATH from $UPSTREAM_SOURCE"
