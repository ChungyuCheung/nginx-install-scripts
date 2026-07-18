#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Nginx 安裝脚本 (Debian/Ubuntu) ===${NC}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

apt update

apt install -y curl gnupg2 ca-certificates lsb-release

curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg > /dev/null

echo -e "${GREEN}簽名鍵已添加${NC}"

. /etc/os-release
if [ "$ID" = "ubuntu" ]; then
    DISTRO="ubuntu"
else
    DISTRO="debian"
fi

CODENAME=$(lsb_release -cs)

cat > /etc/apt/sources.list.d/nginx.list << 'EOF'
deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/$DISTRO $CODENAME nginx
EOF

cat > /etc/apt/preferences.d/99nginx << 'EOF'
Package: *
Pin: origin nginx.org
Pin-Priority: 900
EOF

apt update
apt install -y nginx

systemctl enable --now nginx

NGINX_VERSION=$(nginx -v 2>&1 | awk '{print $3}')
echo -e "${GREEN}Nginx 安裝完成！ 版本: $NGINX_VERSION${NC}"
