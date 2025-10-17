#!/usr/bin/env bash
# Elastic Stack (Elasticsearch + Kibana + Logstash + Filebeat) - SIEM Ready
# Ubuntu 24.04 (Lab mode: HTTP/no-TLS; enable TLS for production!)

set -euo pipefail

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[-] $*\033[0m" >&2; }

require_root() { [[ $EUID -eq 0 ]] || { err "Run as root"; exit 1; }; }

require_cmds() {
  local req=(curl wget gpg apt)
  for c in "${req[@]}"; do command -v "$c" >/dev/null 2>&1 || { err "Missing: $c"; exit 1; }; done
}

init_defaults() {
  : "${ELASTIC_PASSWORD:=""}"
  : "${ES_HEAP_GB:=2}"
  : "${CLUSTER_NAME:=octasec-cluster}"
  : "${NODE_NAME:=node-1}"
  : "${BIND_IP:=0.0.0.0}"
  : "${KIBANA_PORT:=5601}"
  : "${ES_HTTP_PORT:=9200}"
  : "${LOGSTASH_BEATS_PORT:=5044}"
  : "${UFW_OPEN:=false}"

  if [[ -z "${ELASTIC_PASSWORD}" ]]; then
    ELASTIC_PASSWORD="$(openssl rand -base64 18 | tr -d '\n=+/')!Aa9"
    GENERATED_PASSWORD="true"
  else
    GENERATED_PASSWORD="false"
  fi
}

apt_prep() {
  log "Updating system & prerequisites..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt upgrade -y || true
  apt install -y apt-transport-https ca-certificates gnupg lsb-release software-properties-common
}

add_elastic_repo() {
  log "Adding Elastic 8.x APT repository..."
  install -d -m 0755 /usr/share/keyrings
  wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | gpg --dearmor -o /usr/share/keyrings/elastic-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/elastic-archive-keyring.gpg] https://artifacts.elastic.co/packages/8.x/apt stable main" > /etc/apt/sources.list.d/elastic-8.x.list
  apt update
}

install_stack() {
  log "Installing Elasticsearch, Kibana, Logstash, Filebeat..."
  apt install -y elasticsearch kibana logstash filebeat
}

configure_elasticsearch() {
  log "Configuring Elasticsearch..."
  # ES kernel requirement
  echo "vm.max_map_count=262144" | tee /etc/sysctl.d/99-elastic.conf >/dev/null
  sysctl --system >/dev/null

  # Heap
  mkdir -p /etc/elasticsearch/jvm.options.d
  cat > /etc/elasticsearch/jvm.options.d/heap.options <<EOFH
-Xms${ES_HEAP_GB}g
-Xmx${ES_HEAP_GB}g
EOFH

  # Main config (LAB: no TLS on HTTP/transport)
  cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: ${CLUSTER_NAME}
node.name: ${NODE_NAME}
network.host: ${BIND_IP}
http.port: ${ES_HTTP_PORT}
discovery.type: single-node
xpack.security.enabled: true
xpack.security.http.ssl.enabled: false
xpack.security.transport.ssl.enabled: false
EOF

  # bootstrap password
  /usr/share/elasticsearch/bin/elasticsearch-keystore create || true
  /usr/share/elasticsearch/bin/elasticsearch-keystore remove bootstrap.password >/dev/null 2>&1 || true
  echo "${ELASTIC_PASSWORD}" | /usr/share/elasticsearch/bin/elasticsearch-keystore add -x bootstrap.password

  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl restart elasticsearch

  log "Waiting for Elasticsearch on http://localhost:${ES_HTTP_PORT} ..."
  for i in {1..60}; do
    if curl -sf -u "elastic:${ELASTIC_PASSWORD}" "http://localhost:${ES_HTTP_PORT}" >/dev/null; then
      log "Elasticsearch is up."
      break
    fi
    sleep 2
  done
}

configure_kibana() {
  log "Configuring Kibana..."
  cat > /etc/kibana/kibana.yml <<EOF
server.port: ${KIBANA_PORT}
server.host: "${BIND_IP}"
elasticsearch.hosts: ["http://localhost:${ES_HTTP_PORT}"]
elasticsearch.username: "elastic"
elasticsearch.password: "${ELASTIC_PASSWORD}"
xpack.security.enabled: true
EOF
  systemctl enable kibana
  systemctl restart kibana
}

configure_logstash() {
  log "Configuring Logstash pipeline (Beats -> Elasticsearch)..."
  mkdir -p /etc/logstash/conf.d

  cat > /etc/logstash/conf.d/01-input.conf <<'EOFI'
input {
  beats {
    port => ${LOGSTASH_BEATS_PORT}
  }
}
EOFI
  sed -i "s/\${LOGSTASH_BEATS_PORT}/${LOGSTASH_BEATS_PORT}/g" /etc/logstash/conf.d/01-input.conf

  cat > /etc/logstash/conf.d/10-filter.conf <<'EOFF'
filter {
  # add grok/geoip/useragent here if needed
}
EOFF

  cat > /etc/logstash/conf.d/99-output.conf <<EOFo
output {
  elasticsearch {
    hosts => ["http://localhost:${ES_HTTP_PORT}"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    index => "logs-%{[@metadata][beat]}-%{+YYYY.MM.dd}"
  }
}
EOFo

  systemctl enable logstash
  systemctl restart logstash
}

configure_filebeat() {
  log "Configuring Filebeat + dashboards..."
  filebeat modules enable system >/dev/null 2>&1 || true

  # Ship via Logstash
  sed -i 's|^output.elasticsearch:|#output.elasticsearch:|g' /etc/filebeat/filebeat.yml || true
  sed -i 's|^  hosts: \[.*\]|#  hosts: []|g' /etc/filebeat/filebeat.yml || true
  sed -i 's|^#output.logstash:|output.logstash:|g' /etc/filebeat/filebeat.yml || true
  if grep -q '^  hosts:' /etc/filebeat/filebeat.yml; then
    sed -i "s|^  hosts: \[.*\]|  hosts: [\"localhost:${LOGSTASH_BEATS_PORT}\"]|g" /etc/filebeat/filebeat.yml
  else
    sed -i "/^output.logstash:/a\  hosts: [\"localhost:${LOGSTASH_BEATS_PORT}\"]" /etc/filebeat/filebeat.yml
  fi

  # Load dashboards directly (needs creds)
  filebeat setup \
    -E output.logstash.enabled=false \
    -E output.elasticsearch.hosts=["http://localhost:${ES_HTTP_PORT}"] \
    -E setup.kibana.host="http://localhost:${KIBANA_PORT}" \
    -E setup.kibana.username="elastic" \
    -E setup.kibana.password="${ELASTIC_PASSWORD}" || true

  systemctl enable filebeat
  systemctl restart filebeat
}

maybe_open_firewall() {
  if [[ "${UFW_OPEN}" == "true" ]]; then
    if command -v ufw >/dev/null 2>&1; then
      log "Opening UFW ports: ${KIBANA_PORT}, ${LOGSTASH_BEATS_PORT}, ${ES_HTTP_PORT}"
      ufw allow "${KIBANA_PORT}/tcp" || true
      ufw allow "${LOGSTASH_BEATS_PORT}/tcp" || true
      ufw allow "${ES_HTTP_PORT}/tcp" || true
    else
      warn "ufw not installed; skipping firewall changes."
    fi
  fi
}

post_checks() {
  log "Sanity checks..."
  for i in {1..60}; do
    if curl -sf "http://localhost:${KIBANA_PORT}/api/status" | grep -q '"overall"'; then
      log "Kibana API is responding."
      break
    fi
    sleep 2
  done
  systemctl --no-pager --full status elasticsearch | sed -n '1,12p' || true
  systemctl --no-pager --full status kibana | sed -n '1,12p' || true
  systemctl --no-pager --full status logstash | sed -n '1,12p' || true
  systemctl --no-pager --full status filebeat | sed -n '1,12p' || true
}

post_info() {
  local ip; ip="$(hostname -I | awk '{print $1}')"
  echo
  log "============== DONE =============="
  log "elastic password: ${ELASTIC_PASSWORD}"
  [[ "${GENERATED_PASSWORD}" == "true" ]] && warn "Save this password!"
  echo
  log "Kibana:        http://${ip}:${KIBANA_PORT}"
  log "Elasticsearch: http://${ip}:${ES_HTTP_PORT}"
  log "Logstash Beats: ${ip}:${LOGSTASH_BEATS_PORT}"
  echo "Next:"
  echo "  - Open Kibana → Security app (SIEM)"
  echo "  - Discover/Dashboards → Filebeat System"
  echo "  - Ship more logs to ${ip}:${LOGSTASH_BEATS_PORT}"
}

main() {
  require_root
  require_cmds
  init_defaults
  apt_prep
  add_elastic_repo
  install_stack
  configure_elasticsearch
  configure_kibana
  configure_logstash
  configure_filebeat
  maybe_open_firewall
  post_checks
  post_info
}

main "$@"
