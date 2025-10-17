# Elastic Stack — SIEM Ready (Ubuntu 24.04)

Turn-key installation of **Elasticsearch + Kibana + Logstash + Filebeat** for a SIEM-ready lab/POC on **Ubuntu 24.04**.

## Features
- Installs from the official Elastic 8.x APT repo
- Secures Elasticsearch and Kibana (basic auth)
- Configures Logstash (Beats → Elasticsearch) with daily indices
- Enables Filebeat `system` module and loads Kibana dashboards
- Optional UFW openings for 5601/5044/9200
- Environment variables to customize heap, ports, cluster name, etc.

## Quick Start

```bash
# Clone
git clone https://github.com/<your-user>/elastic-stack-siem-ready.git
cd elastic-stack-siem-ready

# (Optional) set env vars
export ELASTIC_PASSWORD='Str0ng!Passw0rd'
export ES_HEAP_GB=4
export UFW_OPEN='true'

# Run as root
sudo -E bash scripts/install_elastic_stack.sh
```

Kibana → `http://<SERVER_IP>:5601` (user: `elastic`, pass from env or printed at the end).

## Repository Layout

```
.
├─ scripts/
│  └─ install_elastic_stack.sh
├─ logstash/
│  └─ pipelines/
│     ├─ 01-input.conf
│     ├─ 10-filter.conf
│     └─ 99-output.conf
├─ filebeat/
│  └─ filebeat.yml.sample
├─ .env.example
├─ .gitignore
├─ LICENSE
└─ README.md
```

## Customization

- Adjust Logstash pipelines in `logstash/pipelines/` (add grok/geoip/user_agent, etc.).
- Use `filebeat/filebeat.yml.sample` to roll out Filebeat on **remote hosts** (point to Logstash `host:port`).
- For production, enable TLS for Elasticsearch HTTP & transport, and for Kibana.

## Notes

- Tested on Ubuntu 24.04 single-node. For multi-node clusters, remove `discovery.type: single-node` and configure discovery/transport/TLS.
- This repo is intended for lab/POC and can be hardened for production as needed.


---

## Pipelines Included
- **NGINX** (`20-nginx.conf`) — geoip + user agent, supports Filebeat module or raw combined logs.
- **Apache** (`21-apache.conf`) — geoip + user agent, supports Filebeat module or raw combined logs.
- **Windows (Winlogbeat)** (`30-windows.conf`) — lightweight enrichment for common event IDs.

## Remote Hosts — Quick Recipes

### NGINX host (Ubuntu)
```bash
sudo apt install filebeat -y
sudo filebeat modules enable nginx system
# If using modules, edit /etc/filebeat/modules.d/nginx.yml with your log paths if needed
sudo sed -i 's|output.elasticsearch:|#output.elasticsearch:|g' /etc/filebeat/filebeat.yml
sudo sed -i 's|#output.logstash:|output.logstash:|g' /etc/filebeat/filebeat.yml
sudo sed -i '/output.logstash:/a\  hosts: ["LOGSTASH_IP:5044"]' /etc/filebeat/filebeat.yml
sudo systemctl enable --now filebeat
```

### Apache host (Ubuntu)
```bash
sudo apt install filebeat -y
sudo filebeat modules enable apache system
# Edit /etc/filebeat/modules.d/apache.yml if needed
sudo sed -i 's|output.elasticsearch:|#output.elasticsearch:|g' /etc/filebeat/filebeat.yml
sudo sed -i 's|#output.logstash:|output.logstash:|g' /etc/filebeat/filebeat.yml
sudo sed -i '/output.logstash:/a\  hosts: ["LOGSTASH_IP:5044"]' /etc/filebeat/filebeat.yml
sudo systemctl enable --now filebeat
```

### Windows host
1. Download Winlogbeat from Elastic, install as service.
2. Use `winlogbeat/winlogbeat.yml.sample` to point to your Logstash (`LOGSTASH_IP:5044`).
3. (Optional) Run `winlogbeat setup` to load dashboards.

## Dashboards
- Beats modules load **official dashboards** automatically via:
  - `filebeat setup` (Linux) / `winlogbeat setup` (Windows).
- After data arrives, check Kibana:
  - **Dashboards** → search for `Filebeat nginx`, `Filebeat Apache`, `Winlogbeat Security`.
  - **Security** app for SIEM views and detections.
