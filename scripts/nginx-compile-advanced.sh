#!/bin/bash
#
# Nginx 編譯安裝脚本 - 進階版
# 支援多發行版、多架構、交互式安裝目錄、組件選擇、安裝/卸載/升級/回滾
#
# 使用方法:
#   chmod +x nginx-compile-advanced.sh
#   sudo ./nginx-compile-advanced.sh install
#   sudo ./nginx-compile-advanced.sh upgrade
#   sudo ./nginx-compile-advanced.sh uninstall
#   sudo ./nginx-compile-advanced.sh rollback
#

set -euo pipefail

# ==================== 顏色輸出 ====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ==================== 變數 ====================
NGINX_VERSION="1.26.2"
INSTALL_PREFIX=""
CONFIGURE_ARGS=""
DISTRO_ID=""
DISTRO_VERSION=""
ARCH=""

# ==================== 偵測系統與架構 ====================
detect_system() {
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then
        ARCH="x86_64"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]]; then
        ARCH="aarch64"
    else
        error "不支援的架構: $ARCH (目前只支援 x86_64 和 aarch64)"
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
    log "正在安裝編譯依賴（可能需要一點時間）..."
    case "$DISTRO_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq build-essential libpcre3-dev zlib1g-dev libssl-dev wget curl git
            ;;
        centos|rocky|almalinux|rhel)
            if [[ "$DISTRO_VERSION" == 7* ]]; then
                yum install -y -q gcc make pcre-devel zlib-devel openssl-devel wget curl
            else
                dnf install -y -q gcc make pcre2-devel zlib-devel openssl-devel wget curl dnf-plugins-core
            fi
            ;;
        *)
            warn "未知系統，請手動安裝: gcc make pcre-devel zlib-devel openssl-devel wget curl"
            ;;
    esac
    log "依賴安裝完成"
}

# ==================== 交互式取得安裝目錄 ====================
get_install_prefix() {
    echo -e "${YELLOW}請輸入 Nginx 安裝目錄${NC}"
    echo -e "    預設: ${BLUE}/apps/nginx${NC}"
    echo -e "    5 秒倒數後未輸入將自動使用預設值"
    echo -n "> "
    if read -t 5 INSTALL_PREFIX; then
        :
    else
        INSTALL_PREFIX="/apps/nginx"
        echo -e "\n${YELLOW}已自動使用預設目錄: $INSTALL_PREFIX${NC}"
    fi

    # 確保為絕對路徑
    INSTALL_PREFIX=$(realpath -m "$INSTALL_PREFIX" 2>/dev/null || echo "$INSTALL_PREFIX")
    log "安裝目錄設定為: ${BLUE}$INSTALL_PREFIX${NC}"
}

# ==================== 檢查是否已安裝 ====================
check_existing_installation() {
    if [ -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        CURRENT_VER=$("$INSTALL_PREFIX/sbin/nginx" -v 2>&1 | awk '{print $3}')
        warn "在 $INSTALL_PREFIX 中偵測到已安裝的 Nginx: ${YELLOW}$CURRENT_VER${NC}"
        echo -e "是否要繼續？"
        echo "  [1] 升級 (upgrade)   - 備份後安裝新版"
        echo "  [2] 重新安裝 (fresh) - 刪除現有後重新安裝"
        echo "  [3] 取消 (abort)"
        read -p "> " choice
        case $choice in
            1) MODE="upgrade" ;;
            2) MODE="fresh" ;;
            *) error "已取消操作" ;;
        esac
    else
        MODE="install"
    fi
}

# ==================== 選擇組件 ====================
select_components() {
    log "選擇要啟用的 Nginx 模組（健康監測 = stub_status）"
    echo "請選擇數字（多個用空格分隔），直接按 Enter 使用預設 1 2 3 :"
    echo "  1. HTTP Stub Status 健康監測模組 (--with-http_stub_status_module)"
    echo "  2. SSL + HTTP/2"
    echo "  3. Gzip Static 靜態壓縮"
    echo "  4. Stream (TCP/UDP 反向代理)"
    echo "  5. RealIP (取得真實客戶端 IP)"
    echo -n "> "
    read -r choices || choices="1 2 3"

    CONFIGURE_ARGS="--prefix=$INSTALL_PREFIX --user=nginx --group=nginx --with-threads --with-file-aio --with-http_realip_module"

    for choice in $choices; do
        case $choice in
            1) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_stub_status_module" ;;
            2) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_ssl_module --with-http_v2_module" ;;
            3) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_gzip_static_module" ;;
            4) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-stream --with-stream_ssl_module" ;;
            5) CONFIGURE_ARGS="$CONFIGURE_ARGS --with-http_realip_module" ;;
        esac
    done

    log "Configure 參數: $CONFIGURE_ARGS"
}

# ==================== 下載與編譯安裝 ====================
download_and_compile() {
    read -p "輸入想要安裝的 Nginx 版本 (預設 $NGINX_VERSION): " input_ver || true
    if [ -n "$input_ver" ]; then
        NGINX_VERSION="$input_ver"
    fi

    SRC_DIR="/tmp/nginx-build-$NGINX_VERSION"
    rm -rf "$SRC_DIR"
    mkdir -p "$SRC_DIR"

    log "正在下載 nginx-$NGINX_VERSION ..."
    wget -q --show-progress -O "/tmp/nginx-$NGINX_VERSION.tar.gz" "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" || error "下載失敗，請檢查網絡或版本是否正確"

    tar -xzf "/tmp/nginx-$NGINX_VERSION.tar.gz" -C /tmp
    mv "/tmp/nginx-$NGINX_VERSION" "$SRC_DIR"
    cd "$SRC_DIR"

    log "開始 configure & make (請耐心等待，可能需 2-5 分鐘)"
    ./configure $CONFIGURE_ARGS
    make -j"$(nproc)"
    make install

    log "編譯安裝完成！ Nginx $NGINX_VERSION 已安裝到 $INSTALL_PREFIX"
}

# ==================== 建立 nginx 用戶與 systemd 服務 ====================
setup_user_and_service() {
    # 建立 nginx 用戶
    if ! id "nginx" &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$INSTALL_PREFIX" nginx 2>/dev/null || true
    fi

    # 建立 systemd service
    cat > /etc/systemd/system/nginx.service <<EOF
[Unit]
Description=The NGINX HTTP and reverse proxy server
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=$INSTALL_PREFIX/logs/nginx.pid
ExecStartPre=$INSTALL_PREFIX/sbin/nginx -t -q
ExecStart=$INSTALL_PREFIX/sbin/nginx
ExecReload=$INSTALL_PREFIX/sbin/nginx -s reload
ExecStop=$INSTALL_PREFIX/sbin/nginx -s quit
KillMode=mixed

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable nginx >/dev/null 2>&1 || true
    log "systemd 服務已建立並啟用"
}

# ==================== 安裝後處理 ====================
post_install_tasks() {
    mkdir -p "$INSTALL_PREFIX/logs" "$INSTALL_PREFIX/conf" "$INSTALL_PREFIX/html"

    # 如果是新安裝，可以建立簡單的 index.html
    if [ ! -f "$INSTALL_PREFIX/html/index.html" ]; then
        echo "<h1>Nginx 安裝成功</h1>" > "$INSTALL_PREFIX/html/index.html"
    fi

    # 檢測配置
    if "$INSTALL_PREFIX"/sbin/nginx -t; then
        log "配置檢測通過"
    else
        warn "配置檢測失敗，請手動檢查 $INSTALL_PREFIX/conf/nginx.conf"
    fi

    echo -e "\n${GREEN}=== 安裝完成 ===${NC}"
    echo "安裝目錄: $INSTALL_PREFIX"
    echo "啟動服務: systemctl start nginx"
    echo "檢查狀態: systemctl status nginx"
    echo "重新啟動: systemctl restart nginx"
    echo "停止: systemctl stop nginx"
    if [[ "$CONFIGURE_ARGS" == *"stub_status"* ]]; then
        echo "健康監測地址: http://your-ip/nginx_status"
    fi
    echo "配置檔: $INSTALL_PREFIX/conf/nginx.conf"
}

# ==================== 主功能: install ====================
do_install() {
    detect_system
    install_dependencies
    get_install_prefix
    check_existing_installation

    if [ "$MODE" = "fresh" ]; then
        warn "即將刪除現有安裝..."
        rm -rf "$INSTALL_PREFIX"
    fi

    select_components
    download_and_compile
    setup_user_and_service
    post_install_tasks
}

# ==================== 主功能: uninstall ====================
do_uninstall() {
    get_install_prefix
    if [ ! -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        error "在 $INSTALL_PREFIX 中未找到 Nginx 安裝"
    fi

    warn "!!! 即將完全刪除 $INSTALL_PREFIX 及其所有內容 !!!"
    read -p "確定要卸載嗎？ (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log "已取消"
        exit 0
    fi

    systemctl stop nginx 2>/dev/null || true
    systemctl disable nginx 2>/dev/null || true
    rm -f /etc/systemd/system/nginx.service
    systemctl daemon-reload

    rm -rf "$INSTALL_PREFIX"
    log "卸載完成"
}

# ==================== 主功能: upgrade ====================
do_upgrade() {
    detect_system
    get_install_prefix

    if [ ! -x "$INSTALL_PREFIX/sbin/nginx" ]; then
        error "請先執行 install"
    fi

    BACKUP_DIR="$INSTALL_PREFIX/backup/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    log "正在備份現有安裝到 $BACKUP_DIR ..."
    cp -a "$INSTALL_PREFIX/sbin/nginx" "$BACKUP_DIR/nginx.bak" 2>/dev/null || true
    cp -a "$INSTALL_PREFIX/conf" "$BACKUP_DIR/conf.bak" 2>/dev/null || true
    cp -a "$INSTALL_PREFIX/logs" "$BACKUP_DIR/logs.bak" 2>/dev/null || true

    log "備份完成"

    select_components
    download_and_compile

    systemctl restart nginx 2>/dev/null || true
    log "升級完成！如果出現問題可以使用 rollback 回滺"
}

# ==================== 主功能: rollback ====================
do_rollback() {
    get_install_prefix

    LATEST_BACKUP=$(ls -td "$INSTALL_PREFIX/backup/"* 2>/dev/null | head -1 || true)
    if [ -z "$LATEST_BACKUP" ] || [ ! -d "$LATEST_BACKUP" ]; then
        error "沒有找到可用的備份"
    fi

    warn "即將從 $LATEST_BACKUP 回滺"
    read -p "確定回滺嗎？ (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        exit 0
    fi

    systemctl stop nginx 2>/dev/null || true

    if [ -f "$LATEST_BACKUP/nginx.bak" ]; then
        cp -f "$LATEST_BACKUP/nginx.bak" "$INSTALL_PREFIX/sbin/nginx"
    fi
    if [ -d "$LATEST_BACKUP/conf.bak" ]; then
        cp -rf "$LATEST_BACKUP/conf.bak/"* "$INSTALL_PREFIX/conf/" 2>/dev/null || true
    fi

    systemctl start nginx 2>/dev/null || true
    log "回滺完成！已恢復到 $LATEST_BACKUP"
}

# ==================== 主程式 ====================
show_help() {
    echo "Nginx 編譯安裝脚本 - 進階版"
    echo ""
    echo "用法: $0 {install|uninstall|upgrade|rollback}"
    echo ""
    echo "  install     - 安裝 Nginx（交互式）"
    echo "  uninstall   - 卸載 Nginx"
    echo "  upgrade     - 升級（會備份）"
    echo "  rollback    - 從最新備份回滺"
    echo ""
    echo "特點:"
    echo "  - 自動偵測 Ubuntu / Rocky Linux / CentOS 7 / Debian"
    echo "  - 支援 x86_64 和 ARM (aarch64)"
    echo "  - 交互式選擇安裝目錄（5秒倒數預設 /apps/nginx）"
    echo "  - 可選擇健康監測、SSL、HTTP2、Stream 等模組"
    echo "  - 建立 systemd 服務"
}

case "${1:-}" in
    install)
        do_install
        ;;
    uninstall)
        do_uninstall
        ;;
    upgrade)
        do_upgrade
        ;;
    rollback)
        do_rollback
        ;;
    -h|--help|help|*)
        show_help
        ;;
esac
