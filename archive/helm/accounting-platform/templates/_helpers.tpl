{{/*
会计平台 Helm Chart 辅助模板
*/}}

{{/* 生成完整名称 */}}
{{- define "accounting-platform.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 生成服务名称 */}}
{{- define "accounting-platform.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/* 通用标签 */}}
{{- define "accounting-platform.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version | replace "+" "_" }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: accounting-platform
{{- end }}

{{/* 选择器标签 */}}
{{- define "accounting-platform.selectorLabels" -}}
app.kubernetes.io/name: {{ include "accounting-platform.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/* 服务镜像 */}}
{{- define "accounting-platform.image" -}}
{{ .Values.registry }}/{{ .Values.imagePrefix }}-{{ .serviceName }}:{{ .Values.tag }}
{{- end }}
