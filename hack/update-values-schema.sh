#!/usr/bin/env bash
#
# Generate chart/values.schema.json from chart/values.yaml with helm-schema
# (https://github.com/dadav/helm-schema).
#
# - Types and defaults are inferred from values.yaml; `# @schema` comment blocks in
#   values.yaml refine them (enums, pass-through Kubernetes objects, ...).
# - Unknown keys are rejected (additionalProperties: false), so typos fail at install
#   time instead of being silently ignored. No key is required.
# - controllerConfiguration is validated against the spec schema of the
#   ControllerConfiguration CRD shipped in chart/templates/crd/, extracted here and
#   referenced from values.yaml via $ref (see hack/update-controllerconfiguration.sh).
#
# Usage:
#   hack/update-values-schema.sh [--helm-repo DIR] [--check]
#
#   --check   Do not write; exit non-zero if chart/values.schema.json is out of date.
#
# Requirements: yq, jq. helm-schema is installed automatically
# (hack/install-helm-schema.sh) if it is not on PATH at HELM_SCHEMA_VERSION.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELM_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
CHECK=false
export HELM_SCHEMA_VERSION="${HELM_SCHEMA_VERSION:-0.24.0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --helm-repo)
      HELM_REPO="$(cd "${2:?}" && pwd)"
      shift 2
      ;;
    --check)
      CHECK=true
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

CHART_DIR="${HELM_REPO}/chart"
CRD="${CHART_DIR}/templates/crd/controllerconfigurations.promoter.argoproj.io.yaml"
SCHEMA="${CHART_DIR}/values.schema.json"

for tool in yq jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Error: $tool is required." >&2
    exit 1
  fi
done

if ! helm-schema --version 2>/dev/null | grep -qx "helm-schema version ${HELM_SCHEMA_VERSION}"; then
  echo "helm-schema ${HELM_SCHEMA_VERSION} not on PATH; installing..."
  export INSTALL_DIR="${INSTALL_DIR:-${HOME}/.local/bin}"
  bash "$SCRIPT_DIR/install-helm-schema.sh" >/dev/null
  export PATH="$INSTALL_DIR:$PATH"
fi

# Generate in a scratch copy so --check has no side effects. The layout mirrors the repo:
# values.yaml's $ref points at ../.values-schema/ relative to the chart directory.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/chart" "$WORK/.values-schema"
cp "$CHART_DIR/Chart.yaml" "$CHART_DIR/values.yaml" "$WORK/chart/"

# The CRD template wraps the manifest in {{ }} directives on their own lines; drop them
# to get plain YAML. values.controllerConfiguration is rendered verbatim as the CR spec.
grep -v '^[[:space:]]*{{' "$CRD" \
  | yq -o=json '.spec.versions[] | select(.name == "v1alpha1") | .schema.openAPIV3Schema.properties.spec' \
  >"$WORK/.values-schema/controllerconfiguration-spec.schema.json"

(
  cd "$WORK"
  helm-schema --chart-search-root chart --skip-auto-generation required --no-dependencies --log-level warning
)

# values.yaml uses "##" comments; helm-schema strips one "#". Drop the remaining comment
# markers from every description and trim surrounding whitespace.
jq --indent 2 '
  walk(
    if type == "object" and (.description | type) == "string" then
      .description |= (split("\n") | map(sub("^#+ ?"; "")) | join("\n") | sub("^\\s+"; "") | sub("\\s+$"; ""))
    else . end
  )
' "$WORK/chart/values.schema.json" >"$WORK/values.schema.json"

if [[ "$CHECK" == true ]]; then
  if ! diff -u "$SCHEMA" "$WORK/values.schema.json"; then
    echo "Error: $SCHEMA is out of date; run hack/update-values-schema.sh" >&2
    exit 1
  fi
  echo "values.schema.json is up to date."
else
  cp "$WORK/values.schema.json" "$SCHEMA"
  echo "Wrote $SCHEMA"
fi
