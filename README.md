# 🦑 OctaSec – Elastic Stack Lab (Docker Edition)

Turn-key deployment of **Elasticsearch + Logstash + Kibana** using **Docker Compose**.  
This is a ready-to-run SIEM lab for cybersecurity testing, training, and content creation.

---

## 🚀 Quick Install (Ubuntu 24.04 / 24.10)

```bash
cd /opt
sudo apt update && sudo apt install -y wget unzip
sudo wget https://github.com/kremissi/elastic-stack-siem-ready/raw/main/elk-docker-installer.zip
sudo unzip elk-docker-installer.zip -d /opt/elk-docker-installer
cd /opt/elk-docker-installer
chmod +x install_elk_docker.sh
sudo ./install_elk_docker.sh
