#!/usr/bin/env bash
#
# Update chart/templates/extra/controllerconfiguration.yaml from the GitOps
# Promoter upstream config. The kubebuilder helm plugin does not emit this
# resource, so we copy it from upstream and apply Helm metadata/templating.
#
# Usage:
#   ./hack/update-controllerconfiguration.sh --gitops-promoter-repo /path/to/gitops-promoter
#
# Run from the repo root (or from current-repo in CI). The chart is expected at chart/.
# Requires: yq (https://github.com/mikefarah/yq)

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
EXTRA_DIR="$CHART_DIR_ABS/templates/extra"
OUTPUT_FILE="$EXTRA_DIR/controllerconfiguration.yaml"
UPSTREAM_SOURCE="$GITOPS_PROMOTER_REPO/config/config/controllerconfiguration.yaml"

if [[ ! -d "$CHART_DIR_ABS" ]]; then
  echo "Error: chart dir not found: $CHART_DIR_ABS" >&2
  exit 1
fi
if [[ ! -f "$UPSTREAM_SOURCE" ]]; then
  echo "Error: upstream controllerconfiguration not found: $UPSTREAM_SOURCE" >&2
  exit 1
fi

mkdir -p "$EXTRA_DIR"

# Helm metadata block (replaces upstream metadata)
read -r -d '' HELM_HEADER <<'HEADER' || true
apiVersion: promoter.argoproj.io/v1alpha1
kind: ControllerConfiguration
metadata:
  labels:
    app.kubernetes.io/managed-by: {{ .Release.Service }}
    app.kubernetes.io/name: {{ include "promoter.name" . }}
    helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    control-plane: controller-manager
  name: promoter-controller-configuration
  namespace: {{ .Release.Namespace }}
HEADER

# Extract spec from upstream and escape Go template delimiters for Helm.
# In pullRequest.template.title/description, {{ and }} must become {{ "{{" }} and {{ "}}" }}
# so Helm doesn't interpret them (they are for the controller's Go templates).
spec_content=$(yq '.spec' "$UPSTREAM_SOURCE" -o=yaml)
# Escape: }} -> __HELM_RBRACE__, then {{ -> {{ "{{" }}, then __HELM_RBRACE__ -> {{ "}}" }}
spec_escaped=$(echo "$spec_content" | sed 's/}}/__HELM_RBRACE__/g' | sed 's/{{/{{ "{{" }}/g' | sed 's/__HELM_RBRACE__/{{ "}}" }}/g')
# Indent spec for top-level YAML (two spaces)
spec_indented=$(echo "$spec_escaped" | sed 's/^/  /')

{
  echo "$HELM_HEADER"
  echo "spec:"
  echo "$spec_indented"
} > "$OUTPUT_FILE"

echo "Updated $OUTPUT_FILE from $UPSTREAM_SOURCE"
