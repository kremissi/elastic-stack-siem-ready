#!/usr/bin/env bash
set -euo pipefail

echo "[+] Enabling Filebeat modules and setting up dashboards..."

if ! command -v filebeat >/dev/null 2>&1; then
  echo "[-] filebeat not found. Install Filebeat first." >&2
  exit 1
fi

# Enable common modules
sudo filebeat modules enable system || true
sudo filebeat modules enable nginx || true
sudo filebeat modules enable apache || true

: "${KIBANA_HOST:=http://localhost:5601}"
: "${ES_HOST:=http://localhost:9200}"
: "${ES_USER:=elastic}"
: "${ES_PASS:=changeme}"

sudo filebeat setup \
  -E setup.kibana.host="${KIBANA_HOST}" \
  -E output.logstash.enabled=false \
  -E output.elasticsearch.hosts=["${ES_HOST}"] \
  -E setup.kibana.username="${ES_USER}" \
  -E setup.kibana.password="${ES_PASS}" || true

sudo systemctl enable filebeat
sudo systemctl restart filebeat

echo "[+] Done. Modules enabled and dashboards loaded (if reachable)."
