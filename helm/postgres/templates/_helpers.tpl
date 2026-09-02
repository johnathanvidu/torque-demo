{{/*
Chart name. Also used as the plain "app" label, so a single selector still finds
every instance of this chart at once: kubectl get pods -n mcp -l app=postgres
*/}}
{{- define "postgres.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Per-instance resource name. EVERY object this chart creates is named from this,
which is what lets two releases of the chart live in one namespace: Helm refuses
to adopt an object owned by another release ("invalid ownership metadata"), so
fixed names would make the second deployment fail outright.

Precedence:
  fullnameOverride - explicit, wins outright.
  instance         - "<chart>-<instance>". The Torque blueprint passes the
                     environment id here, and builds its in-cluster DNS outputs
                     from the same two pieces, so the two always agree.
  .Release.Name    - fallback for a plain "helm install". Torque's own release
                     names are already unique per environment
                     (<grain-name>-<5 hex>), so this stays collision-free too.
*/}}
{{- define "postgres.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if .Values.instance -}}
{{- printf "%s-%s" (include "postgres.name" .) (.Values.instance | toString) | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Selector labels. These MUST differ between instances: two Services selecting on
the same labels would each round-robin across BOTH deployments' pods, and two
Deployments would fight over the same ReplicaSets. Keyed on the fullname, so
uniqueness comes from the same place the object names do.
*/}}
{{- define "postgres.selectorLabels" -}}
app.kubernetes.io/name: {{ include "postgres.name" . }}
app.kubernetes.io/instance: {{ include "postgres.fullname" . }}
{{- end -}}

{{- define "postgres.labels" -}}
app: {{ include "postgres.name" . }}
{{ include "postgres.selectorLabels" . }}
{{- end -}}
