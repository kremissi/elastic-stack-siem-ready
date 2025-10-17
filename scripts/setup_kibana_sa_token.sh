#!/usr/bin/env bash
set -euo pipefail

log(){ echo -e "\033[1;32m[+] $*\033[0m"; }
err(){ echo -e "\033[1;31m[-] $*\033[0m" >&2; }

: "${KIBANA_PORT:=5601}"
: "${ES_HOST:=http://localhost:9200}"
: "${TOKEN_NAME:=octasec-token}"

require_root(){ [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }; }

create_token(){
  log "Creating Kibana service account token: elastic/kibana/${TOKEN_NAME}"
  /usr/share/elasticsearch/bin/elasticsearch-service-tokens delete elastic/kibana "${TOKEN_NAME}" >/dev/null 2>&1 || true
  SA_LINE="$(/usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana "${TOKEN_NAME}")"
  TOKEN="${SA_LINE##*= }"
  [[ -n "${TOKEN}" ]] || { err "Failed to obtain token"; exit 1; }
  echo "${TOKEN}"
}

write_kibana_yml(){
  local token="$1"
  log "Writing minimal /etc/kibana/kibana.yml"
  sed -i '/^elasticsearch\.username/d;/^elasticsearch\.password/d;/^elasticsearch\.serviceAccountToken/d;/^xpack\.security\./d' /etc/kibana/kibana.yml 2>/dev/null || true
  cat > /etc/kibana/kibana.yml <<EOF
server.port: ${KIBANA_PORT}
server.host: "0.0.0.0"
elasticsearch.hosts: ["${ES_HOST}"]
elasticsearch.serviceAccountToken: "${token}"
EOF
}

restart_kibana(){
  log "Restarting Kibana"
  systemctl reset-failed kibana || true
  systemctl daemon-reload
  systemctl restart kibana
  for i in {1..60}; do
    if curl -sf "http://localhost:${KIBANA_PORT}/api/status" >/dev/null; then
      log "Kibana is up on http://$(hostname -I | awk '{print $1}'):${KIBANA_PORT}"
      return
    fi
    sleep 2
  done
  err "Kibana did not start. Check: journalctl -u kibana -n 120"
  exit 1
}

require_root
TOKEN_VAL="$(create_token)"
write_kibana_yml "${TOKEN_VAL}"
restart_kibana
