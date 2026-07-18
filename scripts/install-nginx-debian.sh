#!/bin/bash
#
# Nginx 安裝脚本 - Debian / Ubuntu 系統
# 使用官方 Nginx 倉庫安裝最新穩定版本
#

set -e

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Nginx 安裝脚本開始 ===${NC}"

# 檢查是否為 root 或有 sudo
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}正在使用 sudo ...${NC}"
    exec sudo "$0" "$@"
fi

# 更新系統
apt update

# 安裝前提
apt install -y curl gnupg2 ca-certificates lsb-release debian-archive-keyring 2>/dev/null || \
apt install -y curl gnupg2 ca-certificates lsb-release ubuntu-keyring

# 添加 Nginx 簽名鍵
curl -fsSL https://nginx.org/keys/nginx_signing.key | gpg --dearmor | tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null

# 驗證鍵指紋
fingerprint=$(gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg 2>/dev/null | grep -o '573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62' || true)
if [ -z "$fingerprint" ]; then
    echo -e "${RED}鍵指紋驗證失敗！${NC}"
    exit 1
fi
echo -e "${GREEN}簽名鍵正確添加${NC}"

# 檢測浦系
. /etc/os-release
if [ "$ID" = "ubuntu" ]; then
    DISTRO="ubuntu"
elif [ "$ID" = "debian" ]; then
    DISTRO="debian"
else
    echo -e "${YELLOW}未支援的 Debian 系統，嘗試使用 ubuntu 倉庫...${NC}"
    DISTRO="ubuntu"
fi

CODENAME=$(lsb_release -cs)

# 添加 Nginx 倉庫
cat > /etc/apt/sources.list.d/nginx.list <<EOF
de b [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] https://nginx.org/packages/$DISTRO $CODENAME nginx
EOF

echo -e "${GREEN}Nginx 倉庫已添加 (${DISTRO} $CODENAME)${NC}"

# 設定 pinning 優先級
cat > /etc/apt/preferences.d/99nginx <<EOF
Package: *
Pin: origin nginx.org
Pin: release o=nginx
Pin-Priority: 900
EOF

# 更新并安裝 Nginx
apt update
apt install -y nginx

# 啟動並設定自動啟動
systemctl enable --now nginx

# 驗證安裝
NGINX_VERSION=$(nginx -v 2>&1 | awk '{print $3}')
echo -e "${GREEN}=== Nginx 安裝完成 ===${NC}"
echo -e "版本: ${YELLOW}$NGINX_VERSION${NC}"
echo -e "狀態: $(systemctl is-active nginx)"
echo -e "自動啟動: $(systemctl is-enabled nginx)"

echo -e "\n${GREEN}安裝完成！使用 nginx -t 檢查配置，然後重新啟動服務${NC}"
