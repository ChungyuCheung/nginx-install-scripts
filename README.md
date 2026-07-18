# Nginx 安裝脚本

這個倉庫提供多種 Linux 發行版的 Nginx 安裝脚本，主要使用官方 Nginx 倉庫以獲取最新穩定版本。

## 支援的系統

- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12
- CentOS 7 / 8 / 9
- Rocky Linux 8 / 9
- AlmaLinux 8 / 9
- RHEL 7 / 8 / 9

## 使用方法

### 1. Ubuntu / Debian 系統

```bash
# 下載脚本
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/install-nginx-debian.sh -O install-nginx.sh

# 給予執行權限
chmod +x install-nginx.sh

# 執行安裝（需要 sudo 權限）
sudo ./install-nginx.sh
```

### 2. CentOS / Rocky Linux / RHEL 系統

```bash
wget https://raw.githubusercontent.com/ChungyuCheung/nginx-install-scripts/main/scripts/install-nginx-rhel.sh -O install-nginx.sh
chmod +x install-nginx.sh
sudo ./install-nginx.sh
```

## 注意事項

- 脚本會自動添加官方 Nginx 倉庫，以安裝最新穩定版本
- 安裝後，Nginx 會自動啟動並設定為開機自動
- 可以使用 `nginx -v` 檢查版本
- 如果需要自定義配置，請編輯 `/etc/nginx/nginx.conf`
- 重新啟動： `sudo systemctl restart nginx`

## 脚本特點

- 支援多種浦系自動辨別
- 使用官方簽名鍵和倉庫
- 安裝後清理暫存檔案
- 提供簡單的驗證測試

## 貢獻

歡迎提交 Pull Request 或發現問題！
