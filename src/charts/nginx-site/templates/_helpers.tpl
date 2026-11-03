{{/* Selector labels. "app" is also the label Istio's telemetry keys on. */}}
{{- define "nginx-site.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}

{{- define "nginx-site.labels" -}}
{{ include "nginx-site.selectorLabels" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
