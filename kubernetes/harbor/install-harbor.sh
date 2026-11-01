#!/usr/bin/env bash
#
# Week 4.1: minimale Harbor-install (eigen on-prem registry naast Docker Hub).
# Draait op een eigen Ubuntu-host (niet op CN1/CN2: die draaien al K3s, en Harbor's
# docker-compose-stack (core, portal, registry, redis, postgres) wil daar niet naast
# concurreren om CPU/geheugen op een t2.medium). Gebruik een losse derde instance.
#
# Doet alleen de basis: registry + portal + core, met een self-signed TLS-cert.
# Geen Notary, geen losse Trivy-integratie (die hebben we al in de pipeline, zie week 3).
#
# Gebruik: sudo ./install-harbor.sh <hostname-of-ip> <harbor-admin-wachtwoord>
#
set -euo pipefail

HOST="${1:?Gebruik: sudo ./install-harbor.sh <hostname-of-ip> <admin-wachtwoord>}"
HARBOR_ADMIN_PASSWORD="${2:?Gebruik: sudo ./install-harbor.sh <hostname-of-ip> <admin-wachtwoord>}"
HARBOR_VERSION="v2.14.1"
INSTALL_DIR="/opt/harbor"

[[ $EUID -eq 0 ]] || { echo "Run als root (sudo)." >&2; exit 1; }

echo "[1/5] Docker en de compose-plugin installeren..."
if ! command -v docker >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sh
fi
apt-get update -qq
apt-get install -y -qq docker-compose-plugin openssl

echo "[2/5] Self-signed TLS-certificaat maken voor ${HOST}..."
mkdir -p "${INSTALL_DIR}/certs"
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "${INSTALL_DIR}/certs/harbor.key" \
    -out "${INSTALL_DIR}/certs/harbor.crt" \
    -subj "/CN=${HOST}" \
    -addext "subjectAltName=DNS:${HOST},IP:${HOST}" 2>/dev/null || \
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "${INSTALL_DIR}/certs/harbor.key" \
    -out "${INSTALL_DIR}/certs/harbor.crt" \
    -subj "/CN=${HOST}"

echo "[3/5] Harbor offline installer ${HARBOR_VERSION} downloaden..."
cd /opt
curl -fsSL -o harbor-offline-installer.tgz \
    "https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz"
tar xzf harbor-offline-installer.tgz
mv harbor "${INSTALL_DIR}" 2>/dev/null || true
rm -f harbor-offline-installer.tgz

echo "[4/5] harbor.yml schrijven..."
cp "${INSTALL_DIR}/harbor.yml.tmpl" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^hostname: .*|hostname: ${HOST}|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^  certificate: .*|  certificate: ${INSTALL_DIR}/certs/harbor.crt|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^  private_key: .*|  private_key: ${INSTALL_DIR}/certs/harbor.key|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^harbor_admin_password: .*|harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}|" "${INSTALL_DIR}/harbor.yml"

echo "[5/5] Harbor installeren..."
cd "${INSTALL_DIR}"
./install.sh

echo
echo "Harbor draait op https://${HOST}  (gebruiker: admin)"
echo
echo "Bewijs voor 4.1 - inloggen en een image pushen:"
echo "  docker login ${HOST} -u admin"
echo "  docker tag stensel8/devops-security:latest ${HOST}/library/devops-security:latest"
echo "  docker push ${HOST}/library/devops-security:latest"
echo "  docker pull ${HOST}/library/devops-security:latest"
echo
echo "Zelf-ondertekend certificaat: 'docker login' klaagt over een onvertrouwde CA tenzij"
echo "harbor.crt lokaal aan /etc/docker/certs.d/${HOST}/ca.crt is toegevoegd op de docker-client."
