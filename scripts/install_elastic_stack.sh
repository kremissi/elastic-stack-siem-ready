#!/usr/bin/env bash
# Elastic Stack (Elasticsearch + Kibana + Logstash + Filebeat) - SIEM Ready
# Tested on Ubuntu 24.04 (Noble). Run as root (or with sudo -s).
# Usage:
#   sudo bash install_elastic_stack.sh
# Optional env vars before running:
#   export ELASTIC_PASSWORD='<StrongPassword!>'   # if empty, script will auto-generate
#   export ES_HEAP_GB=4                           # heap in GB (default: 2)
#   export CLUSTER_NAME='octasec-cluster'
#   export NODE_NAME='node-1'
#   export BIND_IP='0.0.0.0'                      # where to listen for ES/Kibana (default: 0.0.0.0)
#   export KIBANA_PORT=5601
#   export ES_HTTP_PORT=9200
#   export LOGSTASH_BEATS_PORT=5044
#   export UFW_OPEN='true'                        # open firewall ports (default: false)

set -euo pipefail

log() { echo -e "\033[1;32m[+] $*\033[0m"; }
warn() { echo -e "\033[1;33m[!] $*\033[0m"; }
err() { echo -e "\033[1;31m[-] $*\033[0m" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    err "Please run as root (sudo -s; then bash $0)"
    exit 1
  fi
}

require_cmds() {
  local req=(curl wget gpg apt)
  for c in "${req[@]}"; do
    command -v "$c" >/dev/null 2>&1 || { err "Missing command: $c"; exit 1; }
  done
}

detect_ubuntu() {
  . /etc/os-release
  if [[ "${ID}" != "ubuntu" || "${VERSION_ID}" != 24.04* ]]; then
    warn "This script is optimized for Ubuntu 24.04; detected: ${PRETTY_NAME}"
  fi
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
  log "Updating system and installing prerequisites..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt upgrade -y
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
  # Set heap
  mkdir -p /etc/elasticsearch/jvm.options.d
  cat > /etc/elasticsearch/jvm.options.d/heap.options <<EOF
-Xms${ES_HEAP_GB}g
-Xmx${ES_HEAP_GB}g
EOF

  # Main config
  cat > /etc/elasticsearch/elasticsearch.yml <<EOF
cluster.name: ${CLUSTER_NAME}
node.name: ${NODE_NAME}
network.host: ${BIND_IP}
http.port: ${ES_HTTP_PORT}
discovery.type: single-node
xpack.security.enabled: true
# TLS on HTTP can be enabled later if desired (recommended for production).
EOF

  # Set bootstrap password for the 'elastic' superuser before first start
  /usr/share/elasticsearch/bin/elasticsearch-keystore create || true
  # Remove if exists to avoid duplicate prompt
  /usr/share/elasticsearch/bin/elasticsearch-keystore remove bootstrap.password >/dev/null 2>&1 || true
  echo "${ELASTIC_PASSWORD}" | /usr/share/elasticsearch/bin/elasticsearch-keystore add -x bootstrap.password

  systemctl daemon-reload
  systemctl enable elasticsearch
  systemctl start elasticsearch

  log "Waiting for Elasticsearch to respond on http://localhost:${ES_HTTP_PORT} ..."
  for i in {1..60}; do
    if curl -s -u "elastic:${ELASTIC_PASSWORD}" "http://localhost:${ES_HTTP_PORT}" >/dev/null; then
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
server.publicBaseUrl: "http://$(hostname -I | awk '{print $1}'):${KIBANA_PORT}"
EOF

  systemctl enable kibana
  systemctl start kibana
}

configure_logstash() {
  log "Configuring Logstash pipeline (Beats -> Elasticsearch)..."
  mkdir -p /etc/logstash/conf.d

  cat > /etc/logstash/conf.d/01-input.conf <<'EOF'
input {
  beats {
    port => ${LOGSTASH_BEATS_PORT}
  }
}
EOF

  cat > /etc/logstash/conf.d/10-filter.conf <<'EOF'
filter {
  # Place for grok/geoip/useragent etc. For now, pass-through.
}
EOF

  cat > /etc/logstash/conf.d/99-output.conf <<EOF
output {
  elasticsearch {
    hosts => ["http://localhost:${ES_HTTP_PORT}"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    index => "logs-%{[@metadata][beat]}-%{+YYYY.MM.dd}"
  }
}
EOF

  # Replace variable in 01-input.conf
  sed -i "s/\${LOGSTASH_BEATS_PORT}/${LOGSTASH_BEATS_PORT}/g" /etc/logstash/conf.d/01-input.conf

  systemctl enable logstash
  systemctl start logstash
}

configure_filebeat() {
  log "Configuring Filebeat to ship local system logs via Logstash & load dashboards..."
  # Enable basic modules
  filebeat modules enable system >/dev/null 2>&1 || true

  # Point Filebeat to Logstash for runtime shipping
  sed -i 's|^output.elasticsearch:|#output.elasticsearch:|g' /etc/filebeat/filebeat.yml || true
  sed -i 's|^  hosts: \[.*\]|#  hosts: []|g' /etc/filebeat/filebeat.yml || true
  sed -i 's|^#output.logstash:|output.logstash:|g' /etc/filebeat/filebeat.yml || true
  if grep -q '^  hosts:' /etc/filebeat/filebeat.yml; then
    sed -i "s|^  hosts: \[.*\]|  hosts: [\"localhost:${LOGSTASH_BEATS_PORT}\"]|g" /etc/filebeat/filebeat.yml
  else
    sed -i "/^output.logstash:/a\  hosts: [\"localhost:${LOGSTASH_BEATS_PORT}\"]" /etc/filebeat/filebeat.yml
  fi

  # Load Kibana dashboards & index templates directly (requires Elasticsearch/Kibana creds)
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
      log "Opening firewall ports (ufw): ${KIBANA_PORT}, ${LOGSTASH_BEATS_PORT}, ${ES_HTTP_PORT}"
      ufw allow "${KIBANA_PORT}/tcp" || true
      ufw allow "${LOGSTASH_BEATS_PORT}/tcp" || true
      ufw allow "${ES_HTTP_PORT}/tcp" || true
    else
      warn "ufw not installed; skipping firewall changes."
    fi
  else
    warn "Firewall ports not opened (UFW_OPEN!=true). Ensure network access as needed."
  fi
}

post_info() {
  local ip
  ip="$(hostname -I | awk '{print $1}')"
  echo
  log "====================== DONE ======================"
  log "Elastic superuser (elastic) password: ${ELASTIC_PASSWORD}"
  if [[ "${GENERATED_PASSWORD}" == "true" ]]; then
    warn "Password was auto-generated. SAVE IT NOW."
  fi
  echo
  log "Kibana:       http://${ip}:${KIBANA_PORT}"
  log "Elasticsearch: http://${ip}:${ES_HTTP_PORT}"
  log "Logstash Beats input: ${ip}:${LOGSTASH_BEATS_PORT}"
  echo
  log "Next steps (SIEM):"
  echo "  1) Open Kibana → Security (Elastic Security app) → Finish initial setup."
  echo "  2) Verify data under Discover and Dashboards (Filebeat System dashboards)."
  echo "  3) Add more Beats or ship logs from other hosts to ${ip}:${LOGSTASH_BEATS_PORT}."
  echo
}

main() {
  require_root
  require_cmds
  detect_ubuntu
  init_defaults
  apt_prep
  add_elastic_repo
  install_stack
  configure_elasticsearch
  configure_kibana
  configure_logstash
  configure_filebeat
  maybe_open_firewall
  post_info
}

main "$@"
