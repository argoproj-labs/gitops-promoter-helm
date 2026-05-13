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
WRCS_CRD="${CHART_DIR}/templates/crd/webrequestcommitstatuses.promoter.argoproj.io.yaml"
PROM="${CHART_DIR}/templates/prometheus/controller-manager-metrics-monitor.yaml"
MANAGER="${CHART_DIR}/templates/manager/manager.yaml"

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

if [[ -f "$WRCS_CRD" ]]; then
  # v0.28.0 added a doc-string example with nested Go-template directives that
  # kubebuilder leaves unescaped, breaking `helm template`. Wrap them in backtick
  # strings so Helm renders them as literal text instead of evaluating them.
  echo "Applying WebRequestCommitStatus CRD Helm escapes..."
  sed_i \
    's/{{ range \.PromotionStrategy\.Status\.Environments }}/{{ `{{ range .PromotionStrategy.Status.Environments }}` }}/g; s/{{ if eq \.Branch \$\.Branch }}/{{ `{{ if eq .Branch $.Branch }}` }}/g; s/{{ end }}{{ end }}/{{ `{{ end }}{{ end }}` }}/g' \
    "$WRCS_CRD"
fi

if [[ -f "$PROM" ]]; then
  echo "Aligning Prometheus ServiceMonitor app.kubernetes.io/name with metrics Service..."
  sed_i 's/app.kubernetes.io\/name: {{ include "promoter.name" . }}/app.kubernetes.io\/name: service/g' "$PROM"
fi

if [[ -f "$MANAGER" ]]; then
  # kubebuilder helm/v2-alpha emits a literal replica count; chart consumers expect
  # manager.replicas in values.yaml (see chart-diff / CONTRIBUTING). Idempotent if
  # the line is already templated.
  echo "Wiring manager Deployment replicas to .Values.manager.replicas..."
  sed_i 's/^  replicas: 1$/  replicas: {{ .Values.manager.replicas }}/' "$MANAGER"
fi
