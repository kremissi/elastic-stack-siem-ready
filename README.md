# ELK Docker Installer — Elastic 8.19.5 (Lab Mode)

This script installs Docker (if needed) and deploys a single-node **Elastic Stack** (Elasticsearch + Logstash + Kibana) at `/opt/elk-lab`.

## Usage
```bash
unzip elk-docker-installer.zip -d /opt
cd /opt/elk-docker-installer
chmod +x install_elk_docker.sh
sudo ./install_elk_docker.sh
```

Kibana: http://<your-ip>:5601  
Elasticsearch: http://<your-ip>:9200  
Logstash (Beats input): <your-ip>:5044

Default credentials:  
`elastic / OctaSec2025`

## Notes
- Lab mode: Security ON / no TLS (HTTP only)
- Tested on Ubuntu 24.04
