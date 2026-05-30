#!/bin/bash
set -e

# 设置默认端口
VNC_PORT=${VNC_PORT:-5901}
NOVNC_PORT=${NOVNC_PORT:-6080}

# 验证端口号是否为数字
if ! [[ "$VNC_PORT" =~ ^[0-9]+$ ]] || ! [[ "$NOVNC_PORT" =~ ^[0-9]+$ ]]; then
    echo "错误: 端口配置无效 - VNC_PORT=$VNC_PORT, NOVNC_PORT=$NOVNC_PORT"
    exit 1
fi

# 等待VNC服务就绪
echo "等待VNC服务就绪..."
timeout=60
count=0
while ! netstat -ln | grep ":${VNC_PORT}" >/dev/null 2>&1 && [ $count -lt $timeout ]; do
    sleep 1
    count=$((count + 1))
done

if ! netstat -ln | grep ":${VNC_PORT}" >/dev/null 2>&1; then
    echo "错误: VNC服务未就绪，超时等待"
    exit 1
fi

echo "VNC服务已就绪，启动noVNC..."

# 检查noVNC是否可用
if [[ -n "${NOVNC_HOME}" && -d "${NOVNC_HOME}" ]]; then
    echo "noVNC目录: ${NOVNC_HOME}"
    
    # 优先使用自定义启动脚本
    if [[ -f "${NOVNC_HOME}/utils/launch.sh" ]]; then
        echo "使用启动脚本: ${NOVNC_HOME}/utils/launch.sh"
        export VNC_HOST=localhost
        export VNC_PORT="${VNC_PORT}"
        export NOVNC_PORT="${NOVNC_PORT}"
        exec bash "${NOVNC_HOME}/utils/launch.sh"
    # 尝试使用utils/novnc_proxy (如果存在)
    elif [[ -f "${NOVNC_HOME}/utils/novnc_proxy" ]]; then
        echo "使用novnc_proxy: ${NOVNC_HOME}/utils/novnc_proxy"
        exec "${NOVNC_HOME}/utils/novnc_proxy" \
            --vnc localhost:${VNC_PORT} \
            --listen ${NOVNC_PORT}
    # 使用websockify直接启动
    elif command -v websockify >/dev/null 2>&1; then
        echo "使用websockify直接启动..."
        echo "命令: websockify --web=${NOVNC_HOME} ${NOVNC_PORT} localhost:${VNC_PORT}"
        exec websockify --web="${NOVNC_HOME}" ${NOVNC_PORT} localhost:${VNC_PORT}
    else
        echo "错误: 无法找到有效的noVNC启动方式"
        exit 1
    fi
else
    echo "错误: noVNC不可用 (目录: ${NOVNC_HOME})"
    exit 1
fi
