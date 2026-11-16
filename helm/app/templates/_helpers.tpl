{{- define "app.name" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "app.labels" -}}
{{ include "app.selectorLabels" . }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/version: {{ .Values.image.tag | default .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "app.image" -}}
{{- if not .Values.image.tag }}{{ fail "image.tag is required (CI passes the commit SHA)" }}{{ end -}}
{{ .Values.image.repository }}:{{ .Values.image.tag }}
{{- end }}

{{- define "app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}{{ include "app.name" . }}{{ else }}default{{ end }}
{{- end }}

{{/* The container env shared by the Deployment, the migration Job and CronJobs. */}}
{{- define "app.envFrom" -}}
{{- if or .Values.env .Values.envFromSecrets }}
envFrom:
  {{- if .Values.env }}
  - configMapRef:
      name: {{ include "app.name" . }}
  {{- end }}
  {{- range .Values.envFromSecrets }}
  - secretRef:
      name: {{ . }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "app.volumeMounts" -}}
{{- if or .Values.tmpDir .Values.persistence.enabled .Values.extraVolumeMounts }}
volumeMounts:
  {{- if .Values.tmpDir }}
  - {name: tmp, mountPath: /tmp}
  {{- end }}
  {{- if .Values.persistence.enabled }}
  - {name: data, mountPath: {{ .Values.persistence.mountPath }}}
  {{- end }}
  {{- with .Values.extraVolumeMounts }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}

{{- define "app.volumes" -}}
{{- if or .Values.tmpDir .Values.persistence.enabled .Values.extraVolumes }}
volumes:
  {{- if .Values.tmpDir }}
  - {name: tmp, emptyDir: {}}
  {{- end }}
  {{- if .Values.persistence.enabled }}
  - name: data
    persistentVolumeClaim:
      claimName: {{ include "app.name" . }}
  {{- end }}
  {{- with .Values.extraVolumes }}
  {{- toYaml . | nindent 2 }}
  {{- end }}
{{- end }}
{{- end }}

{{/* Pod-level settings shared by every workload. */}}
{{- define "app.podSpecCommon" -}}
serviceAccountName: {{ include "app.serviceAccountName" . }}
automountServiceAccountToken: {{ .Values.serviceAccount.automount }}
securityContext:
  {{- toYaml .Values.podSecurityContext | nindent 2 }}
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- with .Values.affinity }}
affinity:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
