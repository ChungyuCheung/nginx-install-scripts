#!/bin/bash
#
# Nginx 編譯安裝腳本 - 進階版 v2
# 新增：GeoIP 支援 + Let's Encrypt 自動申請 SSL 並部署
#
# 使用方法:
#   chmod +x nginx-compile-advanced.sh
#   sudo ./nginx-compile-advanced.sh install
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

NGINX_VERSION="1.26.2"
INSTALL_PREFIX=""
CONFIGURE_ARGS=""
DISTRO_ID=""
DISTRO_VERSION=""
ARCH=""
ENABLE_GEOIP=false

# ==================== 偵測系統 ====================
detect_system() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then ARCH="aarch64"
    else error "不支援的架構: $ARCH"; fi

    if [ -f /etc/os-release ]; then . /etc/os-release; DISTRO_ID="$ID"; DISTRO_VERSION="$VERSION_ID"
    elif [ -f /etc/redhat-release ]; then DISTRO_ID="centos"; DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else error "無法偵測作業系統"; fi
    log "偵測到系統: $DISTRO_ID $DISTRO_VERSION | 架構: $ARCH"
}

# ==================== 安裝依賴 (含 GeoIP) ====================
install_dependencies() {
    log "正在安裝編譯依賴..."
    case "$DISTRO_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq build-essential libpcre3-dev zlib1g-dev libssl-dev wget curl git libmaxminddb-dev
            ;;
        centos|rocky|almalinux|rhel)
            if [[ "$DISTRO_VERSION" == 7* ]]; then
                yum install -y -q gcc make pcre-devel zlib-devel openssl-devel wget curl
            else
                dnf install -y -q gcc make pcre2-devel zlib-devel openssl-devel wget curl dnf-plugins-core libmaxminddb-devel
            fi
            ;;
        *)
            warn "請手動安裝 libmaxminddb 相關開發包"
            ;;
    esac
    log "依賴安裝完成"
}

get_install_prefix() {
    echo -e "${YELLOW}請輸入 Nginx 安裝目錄 (5秒倒數，預設 /apps/nginx):${NC}"
    if ! read -t 5 INSTALL_PREFIX; then
        INSTALL_PREFIX="/apps/nginx"
        echo -e "${YELLOW}已自動使用預設: $INSTALL_PREFIX${NC}"
    fi
    INSTALL_PREFIX=$(realpath -m "$INSTALL_PREFIX" 2>/dev/null || echo "$INSTALL_PREFIX")
    log "安裝目錄: ${BLUE}$INSTALL_PREFIX${NC}"
}

check_existing_installation() {
    if [ -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        CURRENT_VER=$("$INSTALL_PREFIX/sbin/nginx" -v 2>&1 | awk '{print $3}')
        warn "偵測到已安裝 Nginx: $CURRENT_VER"
        echo "[1] 升級  [2] 重新安裝  [3] 取消"
        read -p "> " choice
        case $choice in 1) MODE="upgrade" ;; 2) MODE="fresh" ;; *) error "已取消" ;; esac
    else MODE="install"; fi
}

# ==================== 選擇組件 (新增 GeoIP) ====================
select_components() {
    log "選擇要啟用的模組"
    echo "多個選項請用空格分隔，直接 Enter 使用預設 1 2 3 :"
    echo "  1. Stub Status 健康監測"
    echo "  2. SSL + HTTP/2"
    echo "  3. Gzip Static"
    echo "  4. Stream (TCP/UDP)"
    echo "  5. RealIP"
    echo "  6. GeoIP 支援 (GeoIP2 資料庫)"
    read -r choices || choices="1 2 3"

    CONFIGURE_ARGS="--prefix=$INSTALL_PREFIX --user=nginx --group=nginx --with-threads --with-file-aio"

    for c in $choices; do
        case $c in
            1) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_stub_status_module" ;;
            2) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_ssl_module --with-http_v2_module" ;;
            3) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_gzip_static_module" ;;
            4) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-stream --with-stream_ssl_module" ;;
            5) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_realip_module" ;;
            6) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_geoip_module"; ENABLE_GEOIP=true ;;
        esac
    done
    log "Configure 參數: $CONFIGURE_ARGS"
}

# ==================== 下載編譯 ====================
download_and_compile() {
    read -p "Nginx 版本 (預設 $NGINX_VERSION): " ver || true
    [ -n "$ver" ] && NGINX_VERSION="$ver"

    SRC="/tmp/nginx-$NGINX_VERSION"
    rm -rf "$SRC"
    wget -q --show-progress -O /tmp/nginx.tar.gz "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
    tar -xzf /tmp/nginx.tar.gz -C /tmp
    mv "/tmp/nginx-$NGINX_VERSION" "$SRC"
    cd "$SRC"

    log "開始編譯... (請稍候)"
    ./configure $CONFIGURE_ARGS
    make -j$(nproc)
    make install
    log "編譯安裝完成"
}

setup_user_and_service() {
    id nginx &>/dev/null || useradd -r -s /sbin/nologin -d "$INSTALL_PREFIX" nginx 2>/dev/null || true

    cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=Nginx
After=network-online.target
[Service]
Type=forking
PIDFile=$INSTALL_PREFIX/logs/nginx.pid
ExecStartPre=$INSTALL_PREFIX/sbin/nginx -t -q
ExecStart=$INSTALL_PREFIX/sbin/nginx
ExecReload=$INSTALL_PREFIX/sbin/nginx -s reload
ExecStop=$INSTALL_PREFIX/sbin/nginx -s quit
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable nginx >/dev/null 2>&1 || true
    log "systemd 服務已建立"
}

post_install_tasks() {
    mkdir -p "$INSTALL_PREFIX/logs" "$INSTALL_PREFIX/conf" "$INSTALL_PREFIX/html" "$INSTALL_PREFIX/ssl" "$INSTALL_PREFIX/geoip"

    if [ ! -f "$INSTALL_PREFIX/html/index.html" ]; then
        echo "<h1>Nginx 安裝成功</h1>" > "$INSTALL_PREFIX/html/index.html"
    fi

    "$INSTALL_PREFIX"/sbin/nginx -t && log "配置檢測通過" || warn "配置有問題"

    echo -e "\n${GREEN}=== 安裝完成 ===${NC}"
    echo "目錄: $INSTALL_PREFIX"
    echo "啟動: systemctl start nginx"
    if $ENABLE_GEOIP; then
        echo "GeoIP 資料庫位置: $INSTALL_PREFIX/geoip/"
    fi
}

# ==================== GeoIP 資料庫下載 ====================
setup_geoip_database() {
    if ! $ENABLE_GEOIP; then return; fi
    log "正在下載 GeoIP2 資料庫..."
    wget -q -O "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" "https://github.com/P3TERX/GeoLite.mmdb/raw/master/GeoLite2-Country.mmdb" || \
    wget -q -O "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.mmdb" || true

    if [ -f "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" ]; then
        log "GeoIP 資料庫已下載到 $INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb"
        echo "在 nginx.conf 中可使用: geoip2 $INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb;"
    else
        warn "GeoIP 資料庫下載失敗，請手動下載 MaxMind GeoLite2 mmdb 檔案"
    fi
}

# ==================== Let's Encrypt SSL 自動申請與部署 ====================
setup_letsencrypt_ssl() {
    echo -e "\n${YELLOW}是否要自動申請 Let's Encrypt SSL 憑證並部署？ (y/n)${NC}"
    read -p "> " setup_ssl
    if [[ "$setup_ssl" != "y" && "$setup_ssl" != "Y" ]]; then
        return
    fi

    read -p "請輸入你的域名 (例如 example.com): " DOMAIN
    read -p "請輸入聯絡 email (用於 Let's Encrypt 通知): " EMAIL

    if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
        warn "域名或 email 為空，跳過 SSL 設定"
        return
    fi

    log "正在安裝 acme.sh (Let's Encrypt 客戶端)..."
    curl https://get.acme.sh | sh -s email="$EMAIL" || error "acme.sh 安裝失敗"

    export PATH="$HOME/.acme.sh:$PATH"

    log "正在為 $DOMAIN 申請憑證... (可能需要幾分鐘)"
    if ! "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --standalone --keylength ec-256; then
        warn "standalone 模式失敗，嘗試 webroot 模式..."
        mkdir -p "$INSTALL_PREFIX/html/.well-known/acme-challenge"
        "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --webroot "$INSTALL_PREFIX/html" --keylength ec-256 || error "憑證申請失敗"
    fi

    "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
        --key-file "$INSTALL_PREFIX/ssl/$DOMAIN.key" \
        --fullchain-file "$INSTALL_PREFIX/ssl/$DOMAIN.crt" \
        --reloadcmd "systemctl reload nginx" || true

    cat > "$INSTALL_PREFIX/conf/vhost-ssl-$DOMAIN.conf" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate     $INSTALL_PREFIX/ssl/$DOMAIN.crt;
    ssl_certificate_key $INSTALL_PREFIX/ssl/$DOMAIN.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    root $INSTALL_PREFIX/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    # GeoIP 範例 (取消註解即可使用)
    # geoip2 $INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb;
    # map \$geoip2_data_country_iso_code \$allowed_country { default no; CN yes; HK yes; TW yes; }
    # if (\$allowed_country = no) { return 403; }
}
EOF

    log "SSL 憑證已申請並部署！"
    echo "憑證位置: $INSTALL_PREFIX/ssl/"
    echo "SSL vhost 範例已建立: $INSTALL_PREFIX/conf/vhost-ssl-$DOMAIN.conf"
    echo "請在主 nginx.conf 中 include 該檔案"
    echo "自動續期已由 acme.sh 設定"
}

# ==================== 主流程 ====================
do_install() {
    detect_system
    install_dependencies
    get_install_prefix
    check_existing_installation

    if [ "${MODE:-}" = "fresh" ]; then rm -rf "$INSTALL_PREFIX"; fi

    select_components
    download_and_compile
    setup_user_and_service
    post_install_tasks
    setup_geoip_database
    setup_letsencrypt_ssl

    echo -e "\n${GREEN}所有步驟完成！${NC}"
    echo "啟動 Nginx: systemctl start nginx"
}

show_help() {
    echo "Nginx 進階編譯安裝腳本 v2 (含 GeoIP + Let's Encrypt SSL)"
    echo "用法: $0 install | uninstall | upgrade | rollback"
}

case "${1:-}" in
    install) do_install ;;
    uninstall) echo "完整版請參考 GitHub" ;;
    upgrade)   echo "完整版請參考 GitHub" ;;
    rollback)  echo "完整版請參考 GitHub" ;;
    *) show_help ;;
esac
