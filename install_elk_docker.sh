#!/usr/bin/env bash
set -euo pipefail

# ===== Config =====
STACK_VERSION="8.19.5"
ELASTIC_PASSWORD="OctaSec2025"
ES_JAVA_OPTS="-Xms2g -Xmx2g"
ES_HTTP_PORT=9200
KIBANA_PORT=5601
LOGSTASH_BEATS_PORT=5044
ROOT_DIR="/opt/elk-lab"

green(){ echo -e "\033[1;32m[+] $*\033[0m"; }
red(){ echo -e "\033[1;31m[-] $*\033[0m"; }

[[ $EUID -eq 0 ]] || { red "Run as root (sudo)"; exit 1; }

install_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    green "Installing Docker Engine + Compose plugin..."
    apt update && apt install -y ca-certificates curl gnupg
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable"       > /etc/apt/sources.list.d/docker.list
    apt update && apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  else
    green "Docker already installed."
  fi
}

kernel_tune() {
  green "Setting vm.max_map_count=262144"
  echo "vm.max_map_count=262144" > /etc/sysctl.d/99-elastic.conf
  sysctl --system >/dev/null
}

write_files() {
  green "Preparing project at ${ROOT_DIR}"
  mkdir -p "${ROOT_DIR}"/{pipelines,kibana,scripts}
  cat > "${ROOT_DIR}/.env" <<ENV
STACK_VERSION=${STACK_VERSION}
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
ES_JAVA_OPTS=${ES_JAVA_OPTS}
LOGSTASH_BEATS_PORT=${LOGSTASH_BEATS_PORT}
ES_HTTP_PORT=${ES_HTTP_PORT}
KIBANA_PORT=${KIBANA_PORT}
ENV

  cat > "${ROOT_DIR}/docker-compose.yml" <<'YML'
name: elk-lab
services:
  es01:
    image: docker.elastic.co/elasticsearch/elasticsearch:${STACK_VERSION}
    container_name: es01
    restart: unless-stopped
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=true
      - xpack.security.http.ssl.enabled=false
      - xpack.security.transport.ssl.enabled=false
      - ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
      - ES_JAVA_OPTS=${ES_JAVA_OPTS}
    ulimits:
      memlock:
        soft: -1
        hard: -1
    volumes:
      - esdata:/usr/share/elasticsearch/data
    ports:
      - "${ES_HTTP_PORT}:9200"
    healthcheck:
      test: ["CMD-SHELL", "curl -s -u elastic:${ELASTIC_PASSWORD} http://localhost:9200 >/dev/null"]
      interval: 10s
      timeout: 5s
      retries: 30

  logstash:
    image: docker.elastic.co/logstash/logstash:${STACK_VERSION}
    container_name: logstash
    depends_on:
      es01:
        condition: service_healthy
    environment:
      - xpack.monitoring.enabled=false
      - LS_JAVA_OPTS=-Xms1g -Xmx1g
      - ES_HOST=http://es01:9200
      - ES_USER=elastic
      - ES_PASS=${ELASTIC_PASSWORD}
      - LOGSTASH_BEATS_PORT=${LOGSTASH_BEATS_PORT}
    ports:
      - "${LOGSTASH_BEATS_PORT}:5044"
    volumes:
      - ./pipelines:/usr/share/logstash/pipeline:ro

  kibana:
    image: docker.elastic.co/kibana/kibana:${STACK_VERSION}
    container_name: kibana
    depends_on:
      es01:
        condition: service_healthy
    ports:
      - "${KIBANA_PORT}:5601"
    volumes:
      - ./kibana/kibana.yml:/usr/share/kibana/config/kibana.yml:ro
    restart: unless-stopped

volumes:
  esdata:
YML

  cat > "${ROOT_DIR}/pipelines/pipeline.conf" <<'CONF'
input { beats { port => ${LOGSTASH_BEATS_PORT} } }
filter { }
output {
  elasticsearch {
    hosts   => [ "${ES_HOST}" ]
    user    => "${ES_USER}"
    password=> "${ES_PASS}"
    index   => "logs-%{[@metadata][beat]}-%{+YYYY.MM.dd}"
  }
}
CONF

  cat > "${ROOT_DIR}/scripts/setup_kibana_token.sh" <<'TOK'
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TOKEN=$(docker exec es01 /usr/share/elasticsearch/bin/elasticsearch-service-tokens create elastic/kibana octasec-token | awk -F' = ' '{print $2}')
if [ -z "${TOKEN:-}" ]; then echo "[-] Failed to obtain service token"; exit 1; fi
mkdir -p kibana
cat > kibana/kibana.yml <<EOF
server.port: 5601
server.host: "0.0.0.0"
elasticsearch.hosts: ["http://es01:9200"]
elasticsearch.serviceAccountToken: "${TOKEN}"
EOF
echo "[+] Wrote kibana/kibana.yml"
docker compose up -d kibana
TOK
  chmod +x "${ROOT_DIR}/scripts/setup_kibana_token.sh"
}

bring_up() {
  green "Bringing up Elasticsearch + Logstash ..."
  cd "${ROOT_DIR}"
  docker compose --env-file .env up -d es01 logstash
  green "Waiting for es01 to become healthy ..."
  sleep 10
  for _ in {1..30}; do
    if docker inspect -f '{{.State.Health.Status}}' es01 2>/dev/null | grep -q healthy; then
      green "es01 is healthy."
      break
    fi
    sleep 3
  done
  green "Creating Kibana service token & starting Kibana ..."
  ./scripts/setup_kibana_token.sh
}

post_info() {
  IP=$(hostname -I | awk '{print $1}')
  echo
  green "============== DONE =============="
  echo "Elasticsearch:  http://${IP}:${ES_HTTP_PORT}"
  echo "Kibana:         http://${IP}:${KIBANA_PORT}"
  echo "Logstash Beats: ${IP}:${LOGSTASH_BEATS_PORT}"
}

main() {
  install_docker
  kernel_tune
  write_files
  bring_up
  post_info
}

main
