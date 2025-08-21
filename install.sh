#!/bin/bash

# 下载地址
DOWNLOAD_URL="https://github.com/bqlpfy/flux-panel/releases/download/gost-latest/gost"
COUNTRY=$(curl -s https://ipinfo.io/country)
if [ "$COUNTRY" = "CN" ]; then
    # 拼接 URL
    DOWNLOAD_URL="https://ghfast.top/${DOWNLOAD_URL}"
fi

# 获取用户输入的配置参数
get_config_params() {
    if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
        echo "请输入配置参数："
        if [[ -z "$SERVER_ADDR" ]]; then
            read -p "服务器地址: " SERVER_ADDR
        fi
        if [[ -z "$SECRET" ]]; then
            read -p "密钥: " SECRET
        fi
        if [[ -z "$SERVER_ADDR" || -z "$SECRET" ]]; then
            echo "❌ 参数不完整，操作取消。"
            exit 1
        fi
    fi
}

# 解析命令行参数
while getopts "a:s:" opt; do
    case $opt in
        a) SERVER_ADDR="$OPTARG" ;;
        s) SECRET="$OPTARG" ;;
        *) echo "❌ 无效参数"; exit 1 ;;
    esac
done

# 主逻辑
main() {
    # 检查是否以root权限运行
    if [ "$EUID" -ne 0 ]; then
        echo "请以root用户或使用 sudo 运行此脚本。"
        exit 1
    fi

    echo "🚀 开始下载并运行 GOST..."
    get_config_params

    # 创建一个临时目录用于存放 gost 可执行文件和配置文件
    TEMP_DIR=$(mktemp -d)
    GOST_PATH="$TEMP_DIR/gost"
    CONFIG_FILE="$TEMP_DIR/config.json"
    
    # 退出时清理临时文件
    trap "echo '🧹 清理临时文件...'; rm -rf '$TEMP_DIR'; echo '✅ 清理完成'; exit" INT TERM EXIT

    # 下载 gost
    echo "⬇️ 下载最新版本 gost 中..."
    curl -L "$DOWNLOAD_URL" -o "$GOST_PATH"
    if [[ ! -f "$GOST_PATH" || ! -s "$GOST_PATH" ]]; then
        echo "❌ 下载失败，请检查网络或下载链接。"
        exit 1
    fi
    chmod +x "$GOST_PATH"
    echo "✅ 下载完成"

    # 打印版本
    echo "🔎 gost 版本：$("$GOST_PATH" -V)"

    # 写入 config.json
    echo "📄 创建配置: config.json"
    cat > "$CONFIG_FILE" <<EOF
{
    "addr": "$SERVER_ADDR",
    "secret": "$SECRET"
}
EOF
    chmod 600 "$CONFIG_FILE"

    echo ""
    echo "==============================================="
    echo "🚀 GOST 正在以前台模式运行..."
    echo "使用 Ctrl+C 退出。"
    echo "==============================================="
    echo ""

    # 前台运行 gost，并使用 trap 捕获中断信号
    "$GOST_PATH" -C "$CONFIG_FILE"
}

# 执行主函数
main
