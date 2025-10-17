# Elastic Stack — SIEM Ready (Ubuntu 24.04, Lab)

Turn‑key installation of **Elasticsearch + Kibana + Logstash + Filebeat** for a SIEM‑ready lab/POC on **Ubuntu 24.04**.

## Features
- Installs from the official Elastic 8.x APT repo
- Secures Elasticsearch (basic auth) and uses **HTTP (no TLS)** for *lab simplicity*
- Configures Logstash (Beats → Elasticsearch) with daily indices
- Enables Filebeat `system` module and loads Kibana dashboards
- Optional UFW openings for 5601/5044/9200
- Env vars to customize heap, ports, cluster name, etc.

## Quick Start
```bash
# Upload repo, then on the server:
sudo -E bash scripts/install_elastic_stack.sh
# (Optional) before running:
export ELASTIC_PASSWORD='Str0ng!Passw0rd'
export ES_HEAP_GB=4
export UFW_OPEN='true'
```

Kibana → `http://<SERVER_IP>:5601` (user: `elastic`, password printed or from env).

## Layout
```
.
├─ scripts/
│  ├─ install_elastic_stack.sh
│  └─ enable_beats_modules.sh
├─ logstash/
│  └─ pipelines/
│     ├─ 01-input.conf
│     ├─ 10-filter.conf
│     ├─ 20-nginx.conf
│     ├─ 21-apache.conf
│     ├─ 30-windows.conf
│     └─ 99-output.conf
├─ filebeat/
│  └─ filebeat.yml.sample
├─ winlogbeat/
│  └─ winlogbeat.yml.sample
├─ .env.example
├─ .gitignore
├─ LICENSE
└─ README.md
```

> **Lab Note**: Installer disables TLS on Elasticsearch HTTP/transport for simplicity.
> For production, enable TLS and adjust Kibana/Beats/Logstash outputs accordingly.
