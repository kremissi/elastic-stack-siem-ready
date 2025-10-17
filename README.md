# Elastic Stack — SIEM Ready (Ubuntu 24.04, Lab, 8.19+)

Turn-key setup of **Elasticsearch + Kibana + Logstash + Filebeat** for a SIEM-ready lab / POC on **Ubuntu 24.04**.

---

## 🚀 Highlights
- Installs from the official Elastic 8.x APT repository
- **Lab mode:** Security enabled but **HTTP (no TLS)** for simplicity
- Configures `vm.max_map_count`, explicit `path.data` and `path.logs`
- Includes Logstash pipelines for nginx, apache, and Windows events
- Sample configs for Filebeat / Winlogbeat
- **Kibana 8.19+ authentication** via **Service Account Token** (no `elastic` user)
- Helper script to enable Beats modules and import Kibana dashboards
- Default lab password: `OctaSec2025` (safe for bash, no `!`)

---

## 🧩 Stack Overview
| Component | Purpose | Port |
|------------|----------|------|
| Elasticsearch | Core data store | `9200` |
| Kibana | Visualization and SIEM interface | `5601` |
| Logstash | Ingest & transform events | `5044` |
| Filebeat | Collects logs & sends via Logstash | — |

---

## ⚙️ Quick Start

```bash
sudo apt update && sudo apt install -y git unzip curl wget gnupg
cd /opt && sudo git clone https://github.com/kremissi/elastic-stack-siem-ready.git
cd elastic-stack-siem-ready && sudo chmod +x scripts/*.sh

# 1️⃣ Install Elastic Stack (Lab Mode)
export ELASTIC_PASSWORD='OctaSec2025' ES_HEAP_GB=4 UFW_OPEN='true'
sudo -E bash scripts/install_elastic_stack.sh

# 2️⃣ Configure Kibana (8.19+)
# Creates a service account token and writes kibana.yml automatically
sudo -E bash scripts/setup_kibana_sa_token.sh

# 3️⃣ Load Dashboards & Enable Filebeat Modules
KIBANA_HOST="http://localhost:5601" ES_HOST="http://localhost:9200" ES_USER="elastic" ES_PASS="${ELASTIC_PASSWORD}" \
sudo -E bash scripts/enable_beats_modules.sh
