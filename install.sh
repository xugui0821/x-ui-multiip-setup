#!/bin/bash

# 下载地址
DOWNLOAD_URL="https://github.com/bqlpfy/flux-panel/releases/download/gost-latest/gost"
INSTALL_DIR="/etc/gost"

# 获取命令行参数
SERVER_ADDR="$1"
SECRET="$2"

# 检查参数是否传入
if [ -z "$SERVER_ADDR" ] || [ -z "$SECRET" ]; then
  echo "❌ 请提供服务器地址和密钥"
  echo "用法：./gost.sh <服务器地址> <密钥>"
  exit 1
fi

# 确保安装目录存在
mkdir -p "$INSTALL_DIR"

# 下载 gost
echo "⬇️ 下载 gost 中..."
curl -L "$DOWNLOAD_URL" -o "$INSTALL_DIR/gost"
if [[ ! -f "$INSTALL_DIR/gost" || ! -s "$INSTALL_DIR/gost" ]]; then
  echo "❌ 下载失败，请检查网络或下载链接。"
  exit 1
fi
chmod +x "$INSTALL_DIR/gost"
echo "✅ 下载完成"

# 写入 config.json (创建新配置文件)
CONFIG_FILE="$INSTALL_DIR/config.json"
echo "📄 创建新配置: config.json"
cat > "$CONFIG_FILE" <<EOF
{
  "addr": "$SERVER_ADDR",
  "secret": "$SECRET"
}
EOF

# 直接前台运行 gost
echo "🚀 启动 gost..."
"$INSTALL_DIR/gost" -C "$CONFIG_FILE"
