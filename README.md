# 🦑 OctaSec – Elastic Stack Lab (Docker Edition)

One-command installer for **Elasticsearch + Logstash + Kibana** using **Docker Compose**.  
Built for cybersecurity professionals, SOC engineers, and labs that need a fast, clean, local SIEM.

---

## 🚀 Quick Installation (Ubuntu 24.04+)

```bash
cd /opt
sudo apt update && sudo apt install -y wget unzip
sudo wget https://github.com/kremissi/elastic-stack-siem-ready/raw/main/elk-docker-installer.zip
sudo unzip elk-docker-installer.zip -d /opt/elk-docker-installer
cd /opt/elk-docker-installer/elk-docker-installer
chmod +x install_elk_docker.sh
sudo ./install_elk_docker.sh
