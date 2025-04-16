#!/bin/bash

# 配置路径
CONFIG_FILE="$(pwd)/config.json"
DB_PATH="/etc/x-ui/x-ui.db"
DEFAULT_START_PORT=10001

# 检查sqlite3是否安装
check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        echo "❌ sqlite3 未安装，尝试自动安装..."
        
        if [[ -f /etc/debian_version ]]; then
            apt-get update && apt-get install -y sqlite3
        elif [[ -f /etc/redhat-release ]]; then
            yum install -y sqlite3
        elif [[ -f /etc/arch-release ]]; then
            pacman -Sy --noconfirm sqlite
        elif [[ -f /etc/alpine-release ]]; then
            apk add sqlite
        else
            echo "无法确定Linux发行版，请手动安装sqlite3"
            exit 1
        fi
        
        if ! command -v sqlite3 &> /dev/null; then
            echo "❌ sqlite3 安装失败，请手动安装后重试"
            exit 1
        else
            echo "✅ sqlite3 安装成功"
        fi
    fi
}

# 获取公网IP
get_public_ips() {
    mapfile -t IP_LIST < <(ip -o -4 addr list | awk '{print $4}' | cut -d/ -f1 | grep -Ev '(^127\.|^10\.|^192\.168\.|^172\.(1[6-9]|2[0-9]|3[0-1]))')

    if [ ${#IP_LIST[@]} -eq 0 ]; then
        echo "❌ 未检测到公网 IPv4 地址，退出"
        exit 1
    fi
}

# 生成Xray配置
generate_config() {
    echo "🧠 生成配置中..."

    read -p "请输入起始端口（默认：$DEFAULT_START_PORT）: " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}

    NEW_CONFIG=$(cat <<EOF
{
  "api": {
    "services": [
      "HandlerService",
      "LoggerService",
      "StatsService"
    ],
    "tag": "api"
  },
  "inbounds": [
    {
      "listen": "127.0.0.1",
      "port": 62789,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "127.0.0.1"
      },
      "tag": "api"
    }
  ],
  "outbounds": [
EOF

    for i in "${!IP_LIST[@]}"; do
        ip="${IP_LIST[$i]}"
        tag="ip$((i+1))"
        comma=","
        [ $i -eq $((${#IP_LIST[@]} - 1)) ] && comma=""

        cat <<EOF
    {
      "tag": "$tag",
      "sendThrough": "$ip",
      "protocol": "freedom",
      "settings": {}
    }$comma
EOF
    done

    cat <<EOF
    ,
    {
      "protocol": "freedom",
      "settings": {}
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "policy": {
    "system": {
      "statsInboundDownlink": true,
      "statsInboundUplink": true
    }
  },
  "routing": {
    "rules": [
EOF

    for i in "${!IP_LIST[@]}"; do
        port=$((START_PORT + i))
        tag="ip$((i+1))"
        comma=","
        [ $i -eq $((${#IP_LIST[@]} - 1)) ] && comma=""

        cat <<EOF
      {
        "inboundTag": [
          "inbound-$port"
        ],
        "outboundTag": "$tag",
        "type": "field"
      }$comma
EOF
    done

    cat <<EOF
      ,
      {
        "inboundTag": [
          "api"
        ],
        "outboundTag": "api",
        "type": "field"
      },
      {
        "ip": [
          "geoip:private"
        ],
        "outboundTag": "blocked",
        "type": "field"
      },
      {
        "outboundTag": "blocked",
        "protocol": [
          "bittorrent"
        ],
        "type": "field"
      }
    ]
  },
  "stats": {}
}
EOF
    )
}

# 保存配置文件
save_config() {
    echo "$NEW_CONFIG" > "$CONFIG_FILE"
    echo "✅ 配置文件已保存到: $CONFIG_FILE"

    echo -e "\n✅ 多 IP 配置完成："
    for i in "${!IP_LIST[@]}"; do
        port=$((START_PORT + i))
        echo "📦 端口 inbound-$port 已绑定出站 IP：${IP_LIST[$i]}"
    done
}

# 检查并更新数据库
update_database() {
    echo "🔄 检查并更新x-ui数据库..."
    
    # 备份数据库
    BACKUP_FILE="${DB_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$DB_PATH" "$BACKUP_FILE"
    echo "📦 数据库已备份到: $BACKUP_FILE"

    # 转义JSON中的单引号
    ESCAPED_CONFIG=$(echo "$NEW_CONFIG" | sed "s/'/''/g")

    # 检查xrayTemplateConfig是否存在
    CONFIG_EXISTS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM settings WHERE key = 'xrayTemplateConfig';")
    
    if [ "$CONFIG_EXISTS" -eq 0 ]; then
        echo "ℹ️ xrayTemplateConfig 不存在，将插入新记录"
        if sqlite3 "$DB_PATH" "INSERT INTO settings (key, value) VALUES ('xrayTemplateConfig', '$ESCAPED_CONFIG');"; then
            echo "✅ 成功插入 xrayTemplateConfig"
        else
            echo "❌ 插入 xrayTemplateConfig 失败"
            exit 1
        fi
    else
        echo "ℹ️ xrayTemplateConfig 已存在，将更新现有记录"
        if sqlite3 "$DB_PATH" "UPDATE settings SET value = '$ESCAPED_CONFIG' WHERE key = 'xrayTemplateConfig';"; then
            echo "✅ 成功更新 xrayTemplateConfig"
        else
            echo "❌ 更新 xrayTemplateConfig 失败"
            exit 1
        fi
    fi
}

# 重启服务
restart_service() {
    echo "🔁 正在重启 x-ui 服务..."
    if systemctl restart x-ui; then
        echo "✅ x-ui 重启成功"
    else
        echo "❌ x-ui 重启失败，请手动检查"
        exit 1
    fi
}

# 主函数
main() {
    check_sqlite3
    get_public_ips
    generate_config
    save_config
    update_database
    restart_service
    
    echo "🎉 所有操作已完成!"
}

# 执行主函数
main
