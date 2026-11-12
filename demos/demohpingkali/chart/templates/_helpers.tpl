{{/* Selector labels. "app" is also the label Istio's telemetry keys on. */}}
{{- define "hping-site.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}

{{- define "hping-site.labels" -}}
{{ include "hping-site.selectorLabels" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}
