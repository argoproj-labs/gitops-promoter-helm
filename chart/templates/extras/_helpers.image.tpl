{{/*
  Renders an image reference from a dict with "repository" and "tag". A repository
  containing "@" is digest-pinned and rendered as-is; otherwise "repository:tag".
  Matches the manager image line kubebuilder generates in manager/manager.yaml.
  Used by hack/apply-post-kubebuilder-chart-fixes.sh (kube-rbac-proxy) and
  hack/update-apiserver-templates.sh (apiserver), so keep the name stable.
*/}}
{{- define "promoter.image" -}}
{{- if contains "@" .repository -}}
{{- .repository -}}
{{- else -}}
{{- printf "%s:%v" .repository .tag -}}
{{- end -}}
{{- end -}}
