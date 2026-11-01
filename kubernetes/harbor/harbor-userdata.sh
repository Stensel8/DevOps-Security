#!/usr/bin/env bash
#
# Week 4.1: EC2 user-data voor een losse Harbor-instance. Dit script draait automatisch bij de
# eerste boot (cloud-init, als root), zonder dat er iemand hoeft in te loggen. Plak dit in
# EC2 -> Launch instance -> Advanced details -> User data.
#
# Haalt zijn eigen publieke hostname op via de instance metadata (IMDSv2), genereert zelf een
# admin-wachtwoord (nooit in user-data zelf, want dat is in platte tekst leesbaar in de
# AWS-console/CLI) en installeert Harbor met een self-signed cert.
#
# Voortgang: /var/log/harbor-install.log (en de standaard cloud-init-log /var/log/cloud-init-output.log)
# Wachtwoord na afloop ophalen: sudo cat /root/harbor-admin-password.txt
#
set -euo pipefail
exec > >(tee -a /var/log/harbor-install.log) 2>&1

echo "[1/6] Netwerk is klaar (cloud-init draait dit script zelf pas na het netwerk-stadium)."
# Geen "cloud-init status --wait" hier: dit script draait zelf als onderdeel van cloud-init's
# 'final'-module. --wait zou dan op zichzelf wachten en nooit verdergaan (zelf tegengekomen
# tijdens het testen: het script hing hier vast totdat ik het process handmatig stopte).

echo "[2/6] Eigen publieke hostname opzoeken via instance metadata (IMDSv2)..."
TOKEN=$(curl -sX PUT "http://169.254.169.254/latest/api/token" \
    -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
HOST=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-hostname")
[ -n "$HOST" ] || HOST=$(curl -sH "X-aws-ec2-metadata-token: $TOKEN" \
    "http://169.254.169.254/latest/meta-data/public-ipv4")
echo "Hostname: ${HOST}"

echo "[3/6] Wachtwoord genereren (nooit in user-data, alleen lokaal op deze instance)..."
HARBOR_ADMIN_PASSWORD=$(openssl rand -base64 18)
echo "${HARBOR_ADMIN_PASSWORD}" > /root/harbor-admin-password.txt
chmod 600 /root/harbor-admin-password.txt

echo "[4/6] Docker en de compose-plugin installeren..."
curl -fsSL https://get.docker.com | sh
apt-get update -qq
apt-get install -y -qq docker-compose-plugin openssl

echo "[5/6] Self-signed TLS-certificaat maken voor ${HOST}..."
INSTALL_DIR="/opt/harbor"
mkdir -p "${INSTALL_DIR}/certs"
openssl req -x509 -nodes -days 365 -newkey rsa:4096 \
    -keyout "${INSTALL_DIR}/certs/harbor.key" \
    -out "${INSTALL_DIR}/certs/harbor.crt" \
    -subj "/CN=${HOST}" \
    -addext "subjectAltName=DNS:${HOST}"

echo "[6/6] Harbor downloaden en installeren..."
HARBOR_VERSION="v2.14.1"
cd /opt
curl -fsSL -o harbor-offline-installer.tgz \
    "https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/harbor-offline-installer-${HARBOR_VERSION}.tgz"
tar xzf harbor-offline-installer.tgz
mv harbor "${INSTALL_DIR}" 2>/dev/null || true
rm -f harbor-offline-installer.tgz

cp "${INSTALL_DIR}/harbor.yml.tmpl" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^hostname: .*|hostname: ${HOST}|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^  certificate: .*|  certificate: ${INSTALL_DIR}/certs/harbor.crt|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^  private_key: .*|  private_key: ${INSTALL_DIR}/certs/harbor.key|" "${INSTALL_DIR}/harbor.yml"
sed -i "s|^harbor_admin_password: .*|harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}|" "${INSTALL_DIR}/harbor.yml"

cd "${INSTALL_DIR}"
./install.sh

echo
echo "Klaar. Harbor draait op https://${HOST}"
echo "Gebruiker: admin, wachtwoord: sudo cat /root/harbor-admin-password.txt"
