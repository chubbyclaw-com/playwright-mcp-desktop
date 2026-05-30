#!/bin/bash
set -e

# Playwright MCP Gateway启动脚本 - 支持自动恢复
# 使用Supergateway将Playwright MCP stdio转换为SSE，支持浏览器自动恢复

# 设置默认端口和目录
PLAYWRIGHT_MCP_PORT=${PLAYWRIGHT_MCP_PORT:-9999}
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/opt/chrome-userdata}
REMOTE_DEBUG_PORT=${REMOTE_DEBUG_PORT:-9222}
DISPLAY=${DISPLAY:-:1}
BROWSER_MANAGER_SCRIPT="/usr/local/bin/browser-manager.sh"

echo "🎭 正在启动Playwright MCP Gateway (支持自动恢复)..."
echo "📍 MCP 端口: ${PLAYWRIGHT_MCP_PORT}"
echo "🌐 Remote Debug 端口: ${REMOTE_DEBUG_PORT}"
echo "💾 Chrome用户数据目录: ${CHROME_USER_DATA_DIR}"
echo "🖥️  显示: ${DISPLAY}"

# 验证端口号是否为数字
if ! [[ "$PLAYWRIGHT_MCP_PORT" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误: MCP端口配置无效 - PLAYWRIGHT_MCP_PORT=$PLAYWRIGHT_MCP_PORT"
    exit 1
fi

if ! [[ "$REMOTE_DEBUG_PORT" =~ ^[0-9]+$ ]]; then
    echo "❌ 错误: Remote Debug端口配置无效 - REMOTE_DEBUG_PORT=$REMOTE_DEBUG_PORT"
    exit 1
fi

# 检查Chrome用户数据目录
if [ ! -d "$CHROME_USER_DATA_DIR" ]; then
    echo "📁 创建Chrome用户数据目录: $CHROME_USER_DATA_DIR"
    mkdir -p "$CHROME_USER_DATA_DIR"
    chmod 755 "$CHROME_USER_DATA_DIR"
fi

# 检查浏览器管理器脚本
if [ ! -f "$BROWSER_MANAGER_SCRIPT" ]; then
    echo "❌ 错误: 未找到浏览器管理器脚本: $BROWSER_MANAGER_SCRIPT"
    exit 1
fi

# 检查Node.js是否可用
if ! command -v node >/dev/null 2>&1; then
    echo "❌ 错误: 未找到Node.js"
    exit 1
fi

if ! command -v npx >/dev/null 2>&1; then
    echo "❌ 错误: 未找到npx"
    exit 1
fi

# 检查Google Chrome是否可用
if ! command -v google-chrome-stable >/dev/null 2>&1; then
    echo "❌ 错误: 未找到Google Chrome"
    exit 1
fi

# 等待显示服务就绪（VNC）
echo "⏳ 等待显示服务就绪..."
timeout=30  # 减少超时时间
max_attempts=$((timeout * 2))  # 0.5秒间隔
count=0
while ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && [ $count -lt $max_attempts ]; do
    sleep 0.5  # 更频繁的检查
    count=$((count + 1))
    if [ $((count % 10)) -eq 0 ]; then  # 每5秒输出状态
        elapsed=$((count / 2))
        echo "⏳ 等待显示服务... (${elapsed}/${timeout}秒)"
    fi
done

if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
    echo "⚠️  警告: 显示服务未就绪，继续启动..."
fi

echo "✅ 显示服务已就绪"

# 设置环境变量
export PLAYWRIGHT_MCP_PORT
export CHROME_USER_DATA_DIR
export REMOTE_DEBUG_PORT
export DISPLAY
export NODE_ENV=production

# Playwright浏览器配置
export PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# 等待浏览器就绪（由 browser-manager 服务负责启动和管理）
echo "🔍 等待浏览器服务就绪..."
timeout=60  # 最多等待1分钟  
max_attempts=$((timeout * 2))  # 0.5秒间隔，所以需要翻倍
count=0
while ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1 && [ $count -lt $max_attempts ]; do
    sleep 0.5  # 更频繁的检查
    count=$((count + 1))
    if [ $((count % 6)) -eq 0 ]; then  # 每3秒输出一次状态
        elapsed=$((count / 2))  # 计算已用秒数
        echo "⏳ 等待浏览器服务... (${elapsed}/${timeout}秒)"
    fi
done

if ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1; then
    echo "❌ 浏览器服务未就绪，请检查 browser-manager 服务状态"
    exit 1
else
    echo "✅ 浏览器服务已就绪"
fi

# 创建自动重连的包装函数
start_mcp_with_auto_recovery() {
    local retry_count=0
    local max_retries=6
    local retry_delay=5
    
    while [ $retry_count -lt $max_retries ]; do
        echo "🚀 启动Playwright MCP服务器 (尝试 $((retry_count + 1))/$max_retries)..."
        echo "🎭 使用 @playwright/mcp@latest"
        echo "🌐 SSE端口: ${PLAYWRIGHT_MCP_PORT}"
        echo "🔗 连接到现有 Chrome 实例 (端口: ${REMOTE_DEBUG_PORT})"
        
        # 检查浏览器是否可用  
        if ! curl -s "http://localhost:${REMOTE_DEBUG_PORT}/json/version" >/dev/null 2>&1; then
            echo "⚠️  浏览器连接失败，等待 browser-manager 服务恢复..."
            echo "💡 浏览器由 browser-manager 服务管理，会自动恢复"
            sleep 5  # 等待 browser-manager 自动恢复
        fi
        
        # 启动 MCP 服务器
        if npx @playwright/mcp@latest \
            --port "${PLAYWRIGHT_MCP_PORT}" \
            --user-data-dir="${CHROME_USER_DATA_DIR}" \
            --browser=chrome \
            --cdp-endpoint="http://localhost:${REMOTE_DEBUG_PORT}" \
            --output-dir=/tmp/playwright-output \
            --host=0.0.0.0; then
            echo "✅ Playwright MCP 服务器启动成功"
            return 0
        else
            echo "❌ Playwright MCP 服务器启动失败"
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                echo "⏳ 等待 ${retry_delay} 秒后重试..."
                sleep $retry_delay
            fi
        fi
    done
    
    echo "❌ MCP 服务器启动失败，已达到最大重试次数"
    return 1
}

echo "🎯 模式: Remote Browser + 自动恢复"
echo "🌐 Remote Debug URL: http://localhost:${REMOTE_DEBUG_PORT}"

# 启动 MCP 服务器（带重试机制）
start_mcp_with_auto_recovery

