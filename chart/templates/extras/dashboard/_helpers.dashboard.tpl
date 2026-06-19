{{/*
  Resolves the dashboard image, defaulting to the manager image when
  dashboard.image overrides are not set (the dashboard and controller share one image).
*/}}
{{- define "promoter.dashboard.image" -}}
{{- $img := .Values.dashboard.image | default dict -}}
{{- $repo := $img.repository | default .Values.manager.image.repository -}}
{{- $tag := $img.tag | default .Values.manager.image.tag | default .Chart.AppVersion -}}
{{- if contains "@" $repo -}}
{{- $repo -}}
{{- else -}}
{{- printf "%s:%s" $repo $tag -}}
{{- end -}}
{{- end -}}
