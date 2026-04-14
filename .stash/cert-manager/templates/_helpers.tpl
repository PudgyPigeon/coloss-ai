{{- define "cert-manager.labels" -}}
app.kubernetes.io/managed-by: {{ .Release.Service }}
platform.engineering/environment: {{ .Values.env | default "sandbox" }}
{{- end }}