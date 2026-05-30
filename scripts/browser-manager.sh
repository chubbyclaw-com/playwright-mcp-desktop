#!/bin/bash

# 浏览器管理脚本 - 支持自动恢复和健康检查
# Browser Manager Script - Auto-recovery and Health Check Support

set -e

# 配置变量
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/root/.chrome-userdata}
REMOTE_DEBUG_PORT=${REMOTE_DEBUG_PORT:-9222}
DISPLAY=${DISPLAY:-:1}
CHROME_PID_FILE="/tmp/chrome-manager.pid"
HEALTH_CHECK_INTERVAL=30
MAX_RESTART_ATTEMPTS=3

# 日志函数
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# 检查浏览器是否正在运行
is_browser_running() {
    local port=$1
    if curl -s "http://localhost:${port}/json/version" >/dev/null 2>&1; then
        return 0  # 浏览器正在运行
    else
        return 1  # 浏览器未运行
    fi
}

# 启动浏览器
start_browser() {
    local attempt=1
    
    while [ $attempt -le $MAX_RESTART_ATTEMPTS ]; do
        log "尝试启动浏览器 (第 $attempt 次尝试)"
        
        # 清理可能残留的进程（更彻底的清理）
        log "清理残留的Chrome进程..."
        
        # 1. 清理指定端口的Chrome进程
        pkill -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
        
        # 2. 清理使用相同用户数据目录的Chrome进程
        pkill -f "chromium.*${CHROME_USER_DATA_DIR}" || true
        
        # 3. 等待进程结束
        sleep 3
        
        # 4. 强制清理遗留进程
        pkill -9 -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
        pkill -9 -f "chromium.*${CHROME_USER_DATA_DIR}" || true
        
        # 5. 清理锁文件和临时文件
        rm -f "${CHROME_USER_DATA_DIR}/SingletonLock" || true
        rm -f "${CHROME_USER_DATA_DIR}/SingletonSocket" || true
        rm -f "${CHROME_USER_DATA_DIR}/SingletonCookie" || true
        
        sleep 2
        
        # 启动浏览器
        DISPLAY=$DISPLAY /usr/local/bin/start-chrome.sh \
            --remote-debugging-port=$REMOTE_DEBUG_PORT \
            --user-data-dir="$CHROME_USER_DATA_DIR" \
            --no-first-run \
            --disable-background-mode \
            --disable-background-timer-throttling \
            --disable-backgrounding-occluded-windows \
            --disable-features=TranslateUI \
            --window-size=1280,720 \
            > /var/log/chrome-manager.log 2>&1 &
        
        local chrome_pid=$!
        echo $chrome_pid > "$CHROME_PID_FILE"
        
        # 等待浏览器启动
        local wait_count=0
        while [ $wait_count -lt 30 ]; do
            if is_browser_running $REMOTE_DEBUG_PORT; then
                log "✅ 浏览器启动成功 (PID: $chrome_pid, Port: $REMOTE_DEBUG_PORT)"
                return 0
            fi
            sleep 1
            wait_count=$((wait_count + 1))
        done
        
        log "❌ 浏览器启动失败 (第 $attempt 次尝试)"
        attempt=$((attempt + 1))
    done
    
    log "❌ 浏览器启动失败，已达到最大重试次数"
    return 1
}

# 停止浏览器
stop_browser() {
    log "正在停止浏览器..."
    
    if [ -f "$CHROME_PID_FILE" ]; then
        local chrome_pid=$(cat "$CHROME_PID_FILE")
        if kill -0 "$chrome_pid" 2>/dev/null; then
            kill "$chrome_pid"
            sleep 3
            if kill -0 "$chrome_pid" 2>/dev/null; then
                kill -9 "$chrome_pid"
            fi
        fi
        rm -f "$CHROME_PID_FILE"
    fi
    
    # 清理所有相关进程（彻底清理）
    log "清理所有Chrome相关进程..."
    pkill -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
    pkill -f "chromium.*${CHROME_USER_DATA_DIR}" || true
    sleep 2
    
    # 强制清理遗留进程
    pkill -9 -f "chromium.*remote-debugging-port=${REMOTE_DEBUG_PORT}" || true
    pkill -9 -f "chromium.*${CHROME_USER_DATA_DIR}" || true
    
    # 清理锁文件
    rm -f "${CHROME_USER_DATA_DIR}/SingletonLock" || true
    rm -f "${CHROME_USER_DATA_DIR}/SingletonSocket" || true  
    rm -f "${CHROME_USER_DATA_DIR}/SingletonCookie" || true
    
    log "✅ 浏览器已停止"
}

# 健康检查并自动恢复
health_check_and_recover() {
    log "🔍 开始健康检查循环 (间隔: ${HEALTH_CHECK_INTERVAL}秒)..."
    
    # 首次检查前短暂等待
    log "⏳ 初始等待..."
    sleep 3
    
    while true; do
        if ! is_browser_running $REMOTE_DEBUG_PORT; then
            log "⚠️  检测到浏览器未运行，开始自动恢复..."
            if start_browser; then
                log "✅ 浏览器自动恢复成功"
            else
                log "❌ 浏览器自动恢复失败"
                # 发送通知或采取其他措施
                curl -s -X POST http://localhost:9999/health/browser-down || true
            fi
        else
            log "✅ 浏览器健康状态正常"
        fi
        sleep $HEALTH_CHECK_INTERVAL
    done
}

# 主函数
main() {
    case "${1:-start}" in
        "start")
            log "🚀 启动浏览器..."
            if start_browser; then
                log "✅ 浏览器启动成功，任务完成"
                exit 0
            else
                log "❌ 浏览器启动失败"
                exit 1
            fi
            ;;
        "stop")
            stop_browser
            ;;
        "restart")
            stop_browser
            sleep 2
            start_browser
            ;;
        "health-check")
            health_check_and_recover
            ;;
        "status")
            if is_browser_running $REMOTE_DEBUG_PORT; then
                log "✅ 浏览器正在运行 (Port: $REMOTE_DEBUG_PORT)"
                exit 0
            else
                log "❌ 浏览器未运行"
                exit 1
            fi
            ;;
        *)
            echo "Usage: $0 {start|stop|restart|health-check|status}"
            exit 1
            ;;
    esac
}

# 信号处理
trap 'log "收到终止信号，正在停止浏览器..."; stop_browser; exit 0' TERM INT

# 执行主函数
main "$@"



