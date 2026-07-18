#!/bin/bash
#
# Nginx 編譯安裝脚本 - 進階版 v2.1
# 功能：多發行版、多架構、GeoIP、Let's Encrypt SSL 自動申請與部署
# 完整支援 install / uninstall / upgrade / rollback
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

# ==================== 偵測系統與架構 ====================
detect_system() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ARCH="aarch64"
    else
        error "不支援的架構: $ARCH"
    fi

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_ID="$ID"
        DISTRO_VERSION="$VERSION_ID"
    elif [ -f /etc/redhat-release ]; then
        DISTRO_ID="centos"
        DISTRO_VERSION=$(grep -oE '[0-9]+' /etc/redhat-release | head -1)
    else
        error "無法偵測作業系統"
    fi
    log "偵測到系統: $DISTRO_ID $DISTRO_VERSION | 架構: $ARCH"
}

# ==================== 安裝編譯依賴 ====================
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
            warn "請手動安裝 libmaxminddb 開發包"
            ;;
    esac
    log "依賴安裝完成"
}

# ==================== 交互式取得安裝目錄 ====================
get_install_prefix() {
    echo -e "${YELLOW}請輸入安裝目錄 (5秒倒數預設 /apps/nginx):${NC}"
    if ! read -t 5 INSTALL_PREFIX; then
        INSTALL_PREFIX="/apps/nginx"
        echo -e "${YELLOW}已自動使用預設值${NC}"
    fi
    INSTALL_PREFIX=$(realpath -m "$INSTALL_PREFIX" 2>/dev/null || echo "$INSTALL_PREFIX")
    log "安裝目錄: ${BLUE}$INSTALL_PREFIX${NC}"
}

# ==================== 檢查是否已安裝 ====================
check_existing_installation() {
    if [ -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        CURRENT_VER=$("$INSTALL_PREFIX/sbin/nginx" -v 2>&1 | awk '{print $3}')
        warn "偵測到已安裝的 Nginx: $CURRENT_VER"
        echo "[1] 升級  [2] 重新安裝  [3] 取消"
        read -p "> " choice
        case $choice in
            1) MODE="upgrade" ;;
            2) MODE="fresh" ;;
            *) error "已取消" ;;
        esac
    else
        MODE="install"
    fi
}

# ==================== 選擇組件 ====================
select_components() {
    log "選擇要啟用的模組"
    echo "多個用空格分隔，直接 Enter 使用預設 1 2 3 :"
    echo "  1. Stub Status 健康監測"
    echo "  2. SSL + HTTP/2"
    echo "  3. Gzip Static"
    echo "  4. Stream (TCP/UDP)"
    echo "  5. RealIP"
    echo "  6. GeoIP 支援"
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

# ==================== 下載與編譯 ====================
download_and_compile() {
    read -p "Nginx 版本 (預設 $NGINX_VERSION): " ver || true
    [ -n "$ver" ] && NGINX_VERSION="$ver"

    SRC_DIR="/tmp/nginx-build-$NGINX_VERSION"
    rm -rf "$SRC_DIR"
    wget -q --show-progress -O /tmp/nginx.tar.gz "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz"
    tar -xzf /tmp/nginx.tar.gz -C /tmp
    mv "/tmp/nginx-$NGINX_VERSION" "$SRC_DIR"
    cd "$SRC_DIR"

    log "開始編譯安裝..."
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
    echo "安裝目錄: $INSTALL_PREFIX"
    echo "啟動: systemctl start nginx"
    if $ENABLE_GEOIP; then
        echo "GeoIP 資料庫: $INSTALL_PREFIX/geoip/"
    fi
}

# ==================== GeoIP 資料庫 ====================
setup_geoip_database() {
    if ! $ENABLE_GEOIP; then return; fi
    log "正在下載 GeoIP 資料庫..."
    wget -q -O "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" "https://github.com/P3TERX/GeoLite.mmdb/raw/master/GeoLite2-Country.mmdb" || \
    wget -q -O "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" "https://dl.miyuru.lk/geoip/maxmind/country/maxmind.mmdb" || true

    if [ -f "$INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb" ]; then
        log "GeoIP 資料庫已下載完成"
    else
        warn "GeoIP 資料庫下載失敗，請手動下載"
    fi
}

# ==================== Let's Encrypt SSL ====================
setup_letsencrypt_ssl() {
    echo -e "\n${YELLOW}是否要自動申請 Let's Encrypt SSL？ (y/n)${NC}"
    read -p "> " ans
    [[ "$ans" != "y" && "$ans" != "Y" ]] && return

    read -p "請輸入域名: " DOMAIN
    read -p "請輸入 email: " EMAIL

    [ -z "$DOMAIN" ] || [ -z "$EMAIL" ] && { warn "域名或 email 為空"; return; }

    log "安裝 acme.sh..."
    curl https://get.acme.sh | sh -s email="$EMAIL" || error "acme.sh 安裝失敗"

    export PATH="$HOME/.acme.sh:$PATH"

    log "正在申請憑證 $DOMAIN ..."
    if ! "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --standalone --keylength ec-256; then
        mkdir -p "$INSTALL_PREFIX/html/.well-known/acme-challenge"
        "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --webroot "$INSTALL_PREFIX/html" --keylength ec-256 || error "申請失敗"
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

    # GeoIP 範例 (可退注解解開)
    # geoip2 $INSTALL_PREFIX/geoip/GeoLite2-Country.mmdb;
}
EOF

    log "SSL 憑證已部署完成！"
    echo "憑證位置: $INSTALL_PREFIX/ssl/"
    echo "vhost 範例: $INSTALL_PREFIX/conf/vhost-ssl-$DOMAIN.conf"
}

# ==================== 完整的 uninstall ====================
do_uninstall() {
    get_install_prefix
    if [ ! -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        error "在 $INSTALL_PREFIX 未找到 Nginx"
    fi

    warn "!!! 即將完全刪除 $INSTALL_PREFIX !!!"
    read -p "確定要卸載嗎？ (yes/no): " confirm
    [ "$confirm" != "yes" ] && { log "已取消"; exit 0; }

    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    rm -f /etc/systemd/system/nginx.service
    systemctl daemon-reload

    rm -rf "$INSTALL_PREFIX"
    log "卸載完成"
}

# ==================== 完整的 upgrade ====================
do_upgrade() {
    detect_system
    get_install_prefix
    if [ ! -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        error "請先執行 install"
    fi

    BACKUP_DIR="$INSTALL_PREFIX/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    log "正在備份到 $BACKUP_DIR ..."
    cp -a "$INSTALL_PREFIX/sbin/nginx" "$BACKUP_DIR/nginx.bak" 2>/dev/null || true
    cp -a "$INSTALL_PREFIX/conf" "$BACKUP_DIR/conf.bak" 2>/dev/null || true
    cp -a "$INSTALL_PREFIX/logs" "$BACKUP_DIR/logs.bak" 2>/dev/null || true

    log "備份完成"

    select_components
    download_and_compile

    systemctl restart nginx 2>/dev/null || true
    log "升級完成！可以使用 rollback 回滺"
}

# ==================== 完整的 rollback ====================
do_rollback() {
    get_install_prefix

    LATEST_BACKUP=$(ls -td "$INSTALL_PREFIX/backup/"* 2>/dev/null | head -1 || echo "")
    if [ -z "$LATEST_BACKUP" ] || [ ! -d "$LATEST_BACKUP" ]; then
        error "沒有找到備份"
    fi

    warn "即將從 $LATEST_BACKUP 回滺"
    read -p "確定回滺嗎？ (yes/no): " confirm
    [ "$confirm" != "yes" ] && exit 0

    systemctl stop nginx 2>/dev/null || true

    [ -f "$LATEST_BACKUP/nginx.bak" ] && cp -f "$LATEST_BACKUP/nginx.bak" "$INSTALL_PREFIX/sbin/nginx"
    [ -d "$LATEST_BACKUP/conf.bak" ] && cp -rf "$LATEST_BACKUP/conf.bak/"* "$INSTALL_PREFIX/conf/" 2>/dev/null || true

    systemctl start nginx 2>/dev/null || true
    log "回滺完成！已恢復到 $LATEST_BACKUP"
}

# ==================== 安裝主流程 ====================
do_install() {
    detect_system
    install_dependencies
    get_install_prefix
    check_existing_installation

    if [ "${MODE:-}" = "fresh" ]; then
        warn "即將刪除現有安裝..."
        rm -rf "$INSTALL_PREFIX"
    fi

    select_components
    download_and_compile
    setup_user_and_service
    post_install_tasks
    setup_geoip_database
    setup_letsencrypt_ssl

    echo -e "\n${GREEN}所有步驟完成！${NC}"
    echo "啟動 Nginx: systemctl start nginx"
}

# ==================== 主程式 ====================
show_help() {
    echo "Nginx 進階編譯安裝脚本 v2.1"
    echo ""
    echo "用法: $0 {install|uninstall|upgrade|rollback}"
    echo ""
    echo "  install     - 安裝 Nginx（含 GeoIP 和 SSL）"
    echo "  uninstall   - 卸載 Nginx"
    echo "  upgrade     - 升級（會備份）"
    echo "  rollback    - 從最新備份回滺"
    echo ""
    echo "新增: GeoIP + Let's Encrypt SSL 自動申請與部署"
}

case "${1:-}" in
    install)   do_install ;;
    uninstall) do_uninstall ;;
    upgrade)   do_upgrade ;;
    rollback)  do_rollback ;;
    -h|--help|help|*) show_help ;;
esac
