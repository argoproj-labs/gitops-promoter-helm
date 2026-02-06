#!/usr/bin/env bash
#
# Update Chart.yaml with Artifact Hub CRD and CRD example annotations.
#
# Reads CRD metadata from the chart (via helm template) and example CRs from
# the GitOps Promoter repo's internal/controller/testdata directory, then
# sets artifacthub.io/crds and artifacthub.io/crdsExamples on chart/Chart.yaml.
#
# Usage:
#   ./hack/update-artifacthub-crd-annotations.sh --gitops-promoter-repo /path/to/gitops-promoter
#
# Run from the repo root (or from current-repo in CI). The chart is expected at chart/.
# Requires: helm, yq (https://github.com/mikefarah/yq)

set -euo pipefail

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
CHART_DIR_ABS="$REPO_ROOT/chart"
CHART_YAML="$CHART_DIR_ABS/Chart.yaml"
TESTDATA_DIR="$GITOPS_PROMOTER_REPO/internal/controller/testdata"

if [[ ! -d "$CHART_DIR_ABS" ]]; then
  echo "Error: chart dir not found: $CHART_DIR_ABS" >&2
  exit 1
fi
if [[ ! -f "$CHART_YAML" ]]; then
  echo "Error: Chart.yaml not found: $CHART_YAML" >&2
  exit 1
fi
if [[ ! -d "$TESTDATA_DIR" ]]; then
  echo "Error: gitops-promoter testdata not found: $TESTDATA_DIR" >&2
  exit 1
fi

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
CRDS_DOCS="$TMPDIR/crds_docs.yaml"
CRDS_ARRAY="$TMPDIR/crds_array.yaml"
KINDS_FILE="$TMPDIR/kinds.yaml"
EXAMPLES_DOCS="$TMPDIR/examples_docs.yaml"
EXAMPLES_ARRAY="$TMPDIR/examples_array.yaml"

# 1) Render CRDs with helm template and build Artifact Hub crds list as a YAML array file
helm template release "$CHART_DIR_ABS" --set crd.enable=true 2>/dev/null | yq eval-all '
  select(.kind == "CustomResourceDefinition") |
  {
    "kind": .spec.names.kind,
    "version": (.spec.versions[0].name // "v1alpha1"),
    "name": .spec.names.plural,
    "displayName": .spec.names.kind,
    "description": (.spec.versions[0].schema.openAPIV3Schema.description // (.spec.names.kind + " CRD"))
  }
' -o yaml > "$CRDS_DOCS" || true

if [[ ! -s "$CRDS_DOCS" ]]; then
  echo "Warning: no CRDs extracted from chart." >&2
  echo "[]" > "$CRDS_ARRAY"
else
  yq eval-all '[.]' "$CRDS_DOCS" -o yaml > "$CRDS_ARRAY"
fi

# 2) Build list of CRD kinds for filtering testdata
yq '[.[].kind]' "$CRDS_ARRAY" -o yaml > "$KINDS_FILE"

# 3) Collect example CRs from testdata (promoter.argoproj.io resources whose kind is in CRD list)
> "$EXAMPLES_DOCS"
first=1
while IFS= read -r -d '' f; do
  out=$(yq eval-all '
    . as $doc |
    select($doc.kind != null and ($doc.apiVersion | test("promoter.argoproj.io"))) |
    select(load("'"$KINDS_FILE"'") | ([.[]? == $doc.kind] | any)) |
    $doc
  ' "$f" 2>/dev/null) || true
  if [[ -n "$out" ]]; then
    [[ $first -ne 1 ]] && printf '\n---\n' >> "$EXAMPLES_DOCS"
    echo "$out" >> "$EXAMPLES_DOCS"
    first=0
  fi
done < <(find "$TESTDATA_DIR" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z)

# Slurp and dedupe by kind+name
if [[ ! -s "$EXAMPLES_DOCS" ]]; then
  echo "Warning: no example CRs found in testdata." >&2
  echo "[]" > "$EXAMPLES_ARRAY"
else
  # One example per CRD (first found for each kind); Artifact Hub may not support multiple per CRD
  yq eval-all '[.] | unique_by(.kind)' "$EXAMPLES_DOCS" -o yaml > "$EXAMPLES_ARRAY" 2>/dev/null || echo "[]" > "$EXAMPLES_ARRAY"
fi

# 4) Update Chart.yaml: annotation values must be strings (literal YAML blocks)
PATCH_YAML="$TMPDIR/annotations_patch.yaml"
{
  echo "annotations:"
  echo "  artifacthub.io/crds: |-"
  sed 's/^/    /' "$CRDS_ARRAY"
  echo "  artifacthub.io/crdsExamples: |-"
  sed 's/^/    /' "$EXAMPLES_ARRAY"
} > "$PATCH_YAML"
yq eval '.annotations += load("'"$PATCH_YAML"'").annotations' "$CHART_YAML" -i

echo "Updated $CHART_YAML with artifacthub.io/crds and artifacthub.io/crdsExamples."
