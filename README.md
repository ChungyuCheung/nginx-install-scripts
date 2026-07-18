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

## 進階編譯安裝脚本（推薦 - v2 版本）

新增 **GeoIP** 與 **Let's Encrypt SSL 自動申請並部署** 功能！

```bash
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/nginx-compile-advanced.sh -O nginx-advanced.sh
chmod +x nginx-advanced.sh
sudo ./nginx-advanced.sh install
```

### v2 版本新增功能

- **GeoIP 支援**：可選擇模組 6，自動下載 GeoLite2-Country.mmdb 資料庫
- **Let's Encrypt SSL**：安裝後可自動申請憑證、部署 HTTPS、設定 HTTP 自動跳轉 HTTPS
- 自動建立 acme.sh 自動續期
- SSL vhost 範例檔已生成

### 原有功能

- 自動偵測作業系統與架構（x86_64 / ARM aarch64）
- 交互式選擇安裝目錄（5秒倒數預設 /apps/nginx）
- 可選擇健康監測、SSL+HTTP2、Gzip、Stream、RealIP、GeoIP
- 完整的 install / upgrade / rollback / uninstall
- 自動建立 systemd 服務

## 注意事項

- 普通脚本使用官方倉庫，簡單快速
- 進階脚本使用編譯安裝，適合自訂化需求
- SSL 申請需要域名解析到正常 IP，且 80/443 端口可用
- GeoIP 資料庫建議每月手動更新一次

## 貢獻

歡迎提交 Pull Request 或發現問題！
