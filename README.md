# Nginx 安裝脚本

這個倉庫提供多種 Linux 發行版的 Nginx 安裝脚本，主要使用官方 Nginx 倉庫以獲取最新穩定版本。

## 支援的系統

- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12
- CentOS 7 / 8 / 9
- Rocky Linux 8 / 9
- AlmaLinux 8 / 9
- RHEL 7 / 8 / 9

## 普通安裝脚本（建議新手使用）

### 1. Ubuntu / Debian 系統

```bash
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/install-nginx-debian.sh -O install-nginx.sh
chmod +x install-nginx.sh
sudo ./install-nginx.sh
```

### 2. CentOS / Rocky Linux / RHEL 系統

```bash
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/install-nginx-rhel.sh -O install-nginx.sh
chmod +x install-nginx.sh
sudo ./install-nginx.sh
```

## 進階編譯安裝脚本（推薦）

如果你需要更多自訂化功能（例如自定義安裝目錄、選擇模組、升級與回滺），請使用進階脚本：

```bash
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/nginx-compile-advanced.sh -O nginx-advanced.sh
chmod +x nginx-advanced.sh
sudo ./nginx-advanced.sh install
```

### 進階脚本功能特點

- 自動偵測作業系統與架構（支援 x86_64 和 ARM aarch64）
- 交互式輸入安裝目錄（5秒倒數預設 `/apps/nginx`)
- 可選擇安裝組件（健康監測、SSL+HTTP2、Gzip、Stream、RealIP 等）
- 支援完整的安裝 / 卸載 / 升級 / 回滺 功能
- 自動建立 systemd 服務與 nginx 用戶
- 兇建備份機制（升級時自動備份現有版本）

## 注意事項

- 普通脚本會自動添加官方 Nginx 倉庫，以安裝最新穩定版本
- 進階脚本使用編譯安裝（从源碼編譯），更適合需要自訂化的圴景
- 安裝後，Nginx 會自動啟動並設定為開機自動
- 可以使用 `nginx -v` 檢查版本
- 如果需要自定義配置，請編輯 `/etc/nginx/nginx.conf` 或對應安裝目錄下的 `conf/nginx.conf`
- 重新啟動： `sudo systemctl restart nginx`

## 貢獻

歡迎提交 Pull Request 或發現問題！
