#!/bin/bash

# 配置路径 - 使用当前目录
CONFIG_FILE="$(pwd)/config.json"
DB_PATH="/etc/x-ui/x-ui.db"
DEFAULT_START_PORT=10001

# 检查并安装sqlite3
check_sqlite3() {
    if ! command -v sqlite3 &> /dev/null; then
        echo "❌ sqlite3 未安装，尝试自动安装..."
        
        # 根据不同的Linux发行版使用不同的包管理器
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
        
        # 再次检查是否安装成功
        if ! command -v sqlite3 &> /dev/null; then
            echo "❌ sqlite3 安装失败，请手动安装后重试"
            exit 1
        else
            echo "✅ sqlite3 安装成功"
        fi
    else
        echo "✅ sqlite3 已安装"
    fi
}

# 获取公网IP（排除内网和lo）
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

    # 获取起始端口
    read -p "请输入起始端口（默认：$DEFAULT_START_PORT）: " START_PORT
    START_PORT=${START_PORT:-$DEFAULT_START_PORT}

    # 生成新的Xray配置
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

    # 输出 outbounds
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

    # 追加默认自由出站和黑洞
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

    # routing rules
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

    # 追加 API 和黑洞规则
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

    # 输出绑定信息
    echo -e "\n✅ 多 IP 配置完成："
    for i in "${!IP_LIST[@]}"; do
        port=$((START_PORT + i))
        echo "📦 端口:$port 已绑定出站 IP：${IP_LIST[$i]}"
    done
}

# 更新数据库
update_database() {
    echo "🔄 更新x-ui数据库..."
    # 转义JSON中的单引号
    ESCAPED_CONFIG=$(echo "$NEW_CONFIG" | sed "s/'/''/g")

    # 备份原始数据库
    BACKUP_FILE="${DB_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$DB_PATH" "$BACKUP_FILE"
    echo "📦 数据库已备份到: $BACKUP_FILE"

    # 更新数据库
    if sqlite3 "$DB_PATH" "UPDATE settings SET value = '$ESCAPED_CONFIG' WHERE key = 'xrayTemplateConfig';"; then
        echo "✅ 数据库更新成功"
    else
        echo "❌ 数据库更新失败"
        exit 1
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
    # 检查sqlite3
    check_sqlite3
    
    # 获取公网IP
    get_public_ips
    
    # 生成配置
    generate_config
    
    # 保存配置
    save_config
    
    # 更新数据库
    update_database
    
    # 重启服务
    restart_service
    
    echo "🎉 所有操作已完成!"
}

# 执行主函数
main
