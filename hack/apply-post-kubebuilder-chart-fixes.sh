#!/usr/bin/env bash
#
# Post-process the Helm chart after `kubebuilder edit --plugins=helm/v2-alpha`.
# Keeps CI and local regeneration aligned with hack/regenerate-helm-chart.sh.
#
# Usage:
#   hack/apply-post-kubebuilder-chart-fixes.sh /path/to/chart
#
# Requirements: sed (GNU sed on Linux; BSD sed on macOS supported).
#
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/chart" >&2
  exit 1
fi

CHART_DIR="$(cd "$1" && pwd)"
CRD="${CHART_DIR}/templates/crd/argocdcommitstatuses.promoter.argoproj.io.yaml"
PROM="${CHART_DIR}/templates/prometheus/controller-manager-metrics-monitor.yaml"

if [[ ! -d "$CHART_DIR/templates" ]]; then
  echo "Error: not a chart directory (missing templates/): $CHART_DIR" >&2
  exit 1
fi

# BSD sed (macOS) needs '' for in-place; GNU sed accepts -i and -i''.
if sed --version >/dev/null 2>&1; then
  sed_i() { sed -i "$@"; }
else
  sed_i() { sed -i '' "$@"; }
fi

if [[ -f "$CRD" ]]; then
  echo "Applying ArgoCDCommitStatus CRD Helm escapes..."
  sed_i \
    's/{{- if eq \(.Environment\)/{{ `{{- if eq .Environment` }}/g; s/{{- else if eq \(.Environment\)/{{ `{{- else if eq .Environment` }}/g; s/{{- end -}}/{{ `{{- end -}}` }}/g; s/{{- range \$key, \$value := \.ArgoCDCommitStatus/{{ `{{- range $key, $value := .ArgoCDCommitStatus` }}/g' \
    "$CRD"
fi

if [[ -f "$PROM" ]]; then
  echo "Aligning Prometheus ServiceMonitor app.kubernetes.io/name with metrics Service..."
  sed_i 's/app.kubernetes.io\/name: {{ include "promoter.name" . }}/app.kubernetes.io\/name: service/g' "$PROM"
fi
