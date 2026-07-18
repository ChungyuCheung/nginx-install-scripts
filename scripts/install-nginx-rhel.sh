#!/bin/bash
#
# Nginx 安裝脚本 - RHEL / CentOS / Rocky Linux / AlmaLinux
# 使用官方 Nginx 倉庫
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Nginx 安裝脚本 (RHEL 系統) ===${NC}"

if [ "$(id -u)" -ne 0 ]; then
    exec sudo "$0" "$@"
fi

# 檢測使用 dnf 或 yum
if command -v dnf &> /dev/null; then
    PKG_MGR="dnf"
else
    PKG_MGR="yum"
fi

echo -e "${YELLOW}使用 $PKG_MGR ...${NC}"

# 安裝必要工具
if [ "$PKG_MGR" = "dnf" ]; then
    dnf install -y dnf-plugins-core || true
else
    yum install -y yum-utils || true
fi

# 创建 Nginx repo
cat > /etc/yum.repos.d/nginx.repo << 'EOF'
[nginx-stable]
name=nginx stable repo
baseurl=https://nginx.org/packages/centos/$releasever/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://nginx.org/keys/nginx_signing.key
module_hotfixes=true
EOF

echo -e "${GREEN}Nginx 倉庫已添加${NC}"

# 安裝 Nginx
$PKG_MGR install -y nginx

# 啟動服務
systemctl enable --now nginx

NGINX_VERSION=$(nginx -v 2>&1 | awk '{print $3}')
echo -e "${GREEN}=== Nginx 安裝完成 ===${NC}"
echo -e "版本: ${YELLOW}$NGINX_VERSION${NC}"
echo -e "狀態: $(systemctl is-active nginx)"

echo -e "\n${GREEN}安裝完成！${NC}"
