#!/usr/bin/env bash
#
# Generate the dashboard aggregation apiserver Helm templates from the upstream
# gitops-promoter config/apiserver/ manifests. The kubebuilder helm/v2-alpha plugin
# does NOT emit these resources (the apiserver is a separate kustomize base that is
# never part of config/release/install.yaml), so we "helmify" them here and write
# chart-owned templates under chart/templates/extras/apiserver/.
#
# This mirrors hack/update-controllerconfiguration.sh: it is the generator that
# *resolves* drift (hack/apiserver-diff.sh is the verifier that *detects* it), and it
# is wired into hack/apply-promoter-version-to-chart.sh so version bumps refresh the
# templates automatically.
#
# Transforms applied to the upstream manifests:
#   * namespace promoter-system            -> {{ .Release.Namespace }} (kube-system kept)
#   * fixed resource names (promoter-*)     -> {{ include "promoter.resourceName" ... }}
#   * controller-manager SA reference       -> {{ include "promoter.serviceAccountName" . }}
#   * container image                       -> {{ include "promoter.apiserver.image" . }}
#   * app.kubernetes.io/managed-by: kustomize -> chart managed-by + helm.sh/chart labels
#   * every doc wrapped in {{- if .Values.apiserver.enabled }} ... {{- end }}
#   * serving-cert / TLS handling made cert-mode conditional
#     (insecure | cert-manager | manual) on the Deployment + APIService, and the
#     cert-manager Issuer/Certificate emitted only for the cert-manager mode.
#
# Usage:
#   ./hack/update-apiserver-templates.sh --gitops-promoter-repo /path/to/gitops-promoter
#     [--helm-repo /path/to/gitops-promoter-helm]
#
# Run from the repo root (or pass --helm-repo). Requires: yq (mikefarah), perl.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_HELM_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

GITOPS_PROMOTER_REPO=""
HELM_REPO="$DEFAULT_HELM_REPO"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gitops-promoter-repo)
      GITOPS_PROMOTER_REPO="${2:?--gitops-promoter-repo requires a path}"
      shift 2
      ;;
    --helm-repo)
      HELM_REPO="${2:?--helm-repo requires a path}"
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
if ! command -v yq >/dev/null 2>&1; then
  echo "Error: yq (https://github.com/mikefarah/yq) is required." >&2
  exit 1
fi
if ! command -v perl >/dev/null 2>&1; then
  echo "Error: perl is required." >&2
  exit 1
fi

GITOPS_PROMOTER_REPO="$(cd "$GITOPS_PROMOTER_REPO" && pwd)"
HELM_REPO="$(cd "$HELM_REPO" && pwd)"
SRC="$GITOPS_PROMOTER_REPO/config/apiserver"
BASE="$SRC/base"
OUT="$HELM_REPO/chart/templates/extras/apiserver"

if [[ ! -d "$BASE" ]]; then
  echo "Error: upstream apiserver base not found: $BASE" >&2
  echo "       gitops-promoter >= 0.32.0 is required (it ships config/apiserver/)." >&2
  exit 1
fi

# --- Helm expression building blocks ------------------------------------------------
rn() { printf '{{ include "promoter.resourceName" (dict "suffix" "%s" "context" $) }}' "$1"; }

export RN_APISERVER="$(rn apiserver)"
export RN_AUTHDEL="$(rn apiserver-auth-delegator)"
export RN_EXTAUTH="$(rn apiserver-extension-auth-reader)"
export RN_VIEWER="$(rn promotionstrategydetails-viewer)"
export RN_SELFSIGNED="$(rn apiserver-selfsigned)"
export SA_CONTROLLER='{{ include "promoter.serviceAccountName" . }}'
export NS='{{ .Release.Namespace }}'

# Common text helmification applied to every (already yq-normalized) document:
#   - expand the kustomize managed-by label into chart labels
#   - rewrite fixed promoter-* names to the resourceName helper (longest first)
#   - rewrite the install namespace to the release namespace
helmify_common() {
  perl -pe '
    # app.kubernetes.io/managed-by: kustomize -> chart managed-by + helm.sh/chart
    s!^([ \t]*)app\.kubernetes\.io/managed-by:[ \t]*kustomize[ \t]*$!$1 . qq(app.kubernetes.io/managed-by: {{ .Release.Service }}\n) . $1 . qq(helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }})!e;
    # names (longest first so prefixes do not clobber longer names)
    s!\Qpromoter-apiserver-extension-auth-reader\E!$ENV{RN_EXTAUTH}!g;
    s!\Qpromoter-apiserver-auth-delegator\E!$ENV{RN_AUTHDEL}!g;
    s!\Qpromoter-apiserver-selfsigned\E!$ENV{RN_SELFSIGNED}!g;
    s!\Qpromoter-promotionstrategydetails-viewer\E!$ENV{RN_VIEWER}!g;
    s!\Qpromoter-controller-manager\E!$ENV{SA_CONTROLLER}!g;
    s!\Qpromoter-apiserver\E!$ENV{RN_APISERVER}!g;
    # install namespace -> release namespace
    s!\Qpromoter-system\E!$ENV{NS}!g;
  '
}

# Strip full-line YAML comments from an upstream file (yq leaves trailing foot-comments
# attached to the document, so we remove them at the source for clean, deterministic output).
nocomments() { grep -v '^[[:space:]]*#' "$1"; }

# Wrap a document body (stdin) in the apiserver.enabled gate, with an auto-gen header.
wrap_enabled() {
  local extra_cond="${1:-}"
  local cond='.Values.apiserver.enabled'
  if [[ -n "$extra_cond" ]]; then
    cond="and .Values.apiserver.enabled ($extra_cond)"
  fi
  printf '{{/*\n'
  printf '  AUTO-GENERATED by hack/update-apiserver-templates.sh from\n'
  printf '  gitops-promoter config/apiserver/. DO NOT EDIT MANUALLY; re-run the generator.\n'
  printf '*/}}\n'
  printf '{{- if %s }}\n' "$cond"
  cat
  printf '{{- end }}\n'
}

mkdir -p "$OUT"

echo "Generating apiserver templates from $SRC -> $OUT"

# --- _helpers.apiserver.tpl (static; image resolution) ------------------------------
cat > "$OUT/_helpers.apiserver.tpl" <<'EOF'
{{/*
  AUTO-GENERATED by hack/update-apiserver-templates.sh. DO NOT EDIT MANUALLY.
  Resolves the dashboard apiserver image, defaulting to the manager image when
  apiserver.image overrides are not set (the apiserver and controller share one image).
*/}}
{{- define "promoter.apiserver.image" -}}
{{- $img := .Values.apiserver.image | default dict -}}
{{- $repo := $img.repository | default .Values.manager.image.repository -}}
{{- $tag := $img.tag | default .Values.manager.image.tag | default .Chart.AppVersion -}}
{{- if contains "@" $repo -}}
{{- $repo -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}
EOF

# --- serviceaccount.yaml ------------------------------------------------------------
nocomments "$BASE/serviceaccount.yaml" | yq '.' - | helmify_common | wrap_enabled > "$OUT/serviceaccount.yaml"

# --- service.yaml -------------------------------------------------------------------
nocomments "$BASE/service.yaml" | yq '.' - | helmify_common | wrap_enabled > "$OUT/service.yaml"

# --- rbac.yaml (multi-doc) ----------------------------------------------------------
nocomments "$BASE/rbac.yaml" | yq '.' - | helmify_common | wrap_enabled > "$OUT/rbac.yaml"

# --- apiservice.yaml (cert-mode conditional annotation + spec) ----------------------
nocomments "$BASE/apiservice.yaml" | yq '
  .metadata.__ANNO__ = "x" |
  .spec.__CERT__ = "x"
' - \
  | perl -0777 -pe '
      # metadata sentinel -> cert-manager caBundle injection annotation
      s!^([ \t]*)__ANNO__:.*$!qq(${1}{{- if eq .Values.apiserver.certs.mode "cert-manager" }}\n) . qq(${1}annotations:\n) . qq(${1}  cert-manager.io/inject-ca-from: {{ .Release.Namespace }}/{{ .Values.apiserver.certs.secretName }}\n) . qq(${1}{{- end }})!me;
      # spec sentinel -> insecure / manual caBundle (cert-manager relies on the annotation)
      s!^([ \t]*)__CERT__:.*$!qq(${1}{{- if eq .Values.apiserver.certs.mode "insecure" }}\n) . qq(${1}insecureSkipTLSVerify: true\n) . qq(${1}{{- else if eq .Values.apiserver.certs.mode "manual" }}\n) . qq(${1}caBundle: {{ .Values.apiserver.certs.caBundle | quote }}\n) . qq(${1}{{- end }})!me;
    ' \
  | helmify_common | wrap_enabled > "$OUT/apiservice.yaml"

# --- deployment.yaml (values-driven + cert-mode conditional TLS/serving-cert) -------
nocomments "$BASE/deployment.yaml" | yq '
  .spec.replicas = "__REPLICAS__" |
  .spec.template.spec.securityContext = "__PODSEC__" |
  .spec.template.spec.containers[0].image = "__IMAGE__" |
  .spec.template.spec.containers[0].resources = "__RESOURCES__" |
  .spec.template.spec.containers[0].securityContext = "__CTRSEC__" |
  del(.spec.template.spec.containers[0].args[] | select(test("--tls-"))) |
  .spec.template.spec.containers[0].args += ["__CERT_ARGS__"] |
  del(.spec.template.spec.containers[0].volumeMounts[] | select(.name == "serving-cert")) |
  .spec.template.spec.containers[0].volumeMounts += [{"name": "__CERT_MOUNT__"}] |
  del(.spec.template.spec.volumes[] | select(.name == "serving-cert")) |
  .spec.template.spec.volumes += [{"name": "__CERT_VOLUME__"}]
' - \
  | perl -0777 -pe '
      s!^([ \t]*)replicas: __REPLICAS__[ \t]*$!${1}replicas: {{ .Values.apiserver.replicas }}!m;

      # pod securityContext
      s!^([ \t]*)securityContext: __PODSEC__[ \t]*$!my $c = length($1) + 2; qq(${1}securityContext:\n) . (q( ) x $c) . qq({{- toYaml .Values.apiserver.podSecurityContext | nindent $c }})!me;

      # image + pullPolicy
      s!^([ \t]*)image: __IMAGE__[ \t]*$!qq(${1}image: {{ include "promoter.apiserver.image" . }}\n) . qq(${1}imagePullPolicy: {{ (.Values.apiserver.image).pullPolicy | default .Values.manager.image.pullPolicy }})!me;

      # container resources
      s!^([ \t]*)resources: __RESOURCES__[ \t]*$!my $c = length($1) + 2; qq(${1}resources:\n) . (q( ) x $c) . qq({{- toYaml .Values.apiserver.resources | nindent $c }})!me;

      # container securityContext
      s!^([ \t]*)securityContext: __CTRSEC__[ \t]*$!my $c = length($1) + 2; qq(${1}securityContext:\n) . (q( ) x $c) . qq({{- toYaml .Values.apiserver.securityContext | nindent $c }})!me;

      # cert-mode args: insecure self-signs into --cert-dir; else mount TLS files
      s!^([ \t]*)- __CERT_ARGS__[ \t]*$!qq(${1}{{- if eq .Values.apiserver.certs.mode "insecure" }}\n) . qq(${1}- --cert-dir=/tmp/apiserver-certs\n) . qq(${1}{{- else }}\n) . qq(${1}- --tls-cert-file=/serving-certs/tls.crt\n) . qq(${1}- --tls-private-key-file=/serving-certs/tls.key\n) . qq(${1}{{- end }})!me;

      # cert-mode volumeMount (only when a serving-cert Secret is mounted)
      s!^([ \t]*)- name: __CERT_MOUNT__[ \t]*$!qq(${1}{{- if ne .Values.apiserver.certs.mode "insecure" }}\n) . qq(${1}- name: serving-cert\n) . qq(${1}  mountPath: /serving-certs\n) . qq(${1}  readOnly: true\n) . qq(${1}{{- end }})!me;

      # cert-mode volume (only when a serving-cert Secret is mounted)
      s!^([ \t]*)- name: __CERT_VOLUME__[ \t]*$!qq(${1}{{- if ne .Values.apiserver.certs.mode "insecure" }}\n) . qq(${1}- name: serving-cert\n) . qq(${1}  secret:\n) . qq(${1}    secretName: {{ .Values.apiserver.certs.secretName }}\n) . qq(${1}{{- end }})!me;
    ' \
  | helmify_common | wrap_enabled > "$OUT/deployment.yaml"

# --- certs.yaml (cert-manager Issuer + Certificate; only for cert-manager mode) -----
{
  # Issuer (optional: only when the chart should create it)
  printf '{{- if .Values.apiserver.certs.certManager.issuer.create }}\n'
  nocomments "$SRC/certs-cert-manager/issuer.yaml" | yq '.' - | helmify_common
  printf '{{- end }}\n'
  printf -- '---\n'
  # Certificate (name == secretName so cert-manager.io/inject-ca-from resolves)
  nocomments "$SRC/certs-cert-manager/certificate.yaml" | yq '
    .metadata.name = "__SECRET__" |
    .spec.secretName = "__SECRET__" |
    .spec.issuerRef.name = "__ISSUERNAME__" |
    .spec.issuerRef.kind = "__ISSUERKIND__"
  ' - \
    | ISSUERNAME_EXPR="{{ if .Values.apiserver.certs.certManager.issuer.name }}{{ .Values.apiserver.certs.certManager.issuer.name }}{{ else }}${RN_SELFSIGNED}{{ end }}" \
      perl -0777 -pe '
        s!__SECRET__!{{ .Values.apiserver.certs.secretName }}!g;
        s!__ISSUERNAME__!$ENV{ISSUERNAME_EXPR}!g;
        s!__ISSUERKIND__!{{ .Values.apiserver.certs.certManager.issuer.kind }}!g;
      ' \
    | helmify_common
} | wrap_enabled 'eq .Values.apiserver.certs.mode "cert-manager"' > "$OUT/certs.yaml"

echo "Wrote:"
ls -1 "$OUT"
