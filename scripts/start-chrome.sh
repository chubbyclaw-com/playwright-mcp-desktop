#!/bin/bash

# Chrome startup script
# 参考 ubuntu-vnc-xfce-g3 项目的简化配置

# 设置显示相关环境变量
export DISPLAY=${DISPLAY:-:1}
export LIBGL_ALWAYS_INDIRECT=1

# 设置X11授权文件路径
export XAUTHORITY=${XAUTHORITY:-/root/.Xauthority}

# 设置字体配置路径，确保能加载中文字体
export FONTCONFIG_PATH=/etc/fonts

# 设置Chrome用户数据目录
CHROME_USER_DATA_DIR=${CHROME_USER_DATA_DIR:-/opt/chrome-userdata}

# 创建必要的目录
mkdir -p "$CHROME_USER_DATA_DIR"
chmod 755 "$CHROME_USER_DATA_DIR"

# 等待X服务器就绪
echo "等待X服务器就绪..."
count=0
while ! xdpyinfo >/dev/null 2>&1 && [ $count -lt 30 ]; do
    sleep 1
    count=$((count + 1))
    echo "等待X服务器... ($count/30)"
done

if ! xdpyinfo >/dev/null 2>&1; then
    echo "错误：X服务器未就绪，无法启动Chrome"
    exit 1
fi

echo "X服务器已就绪"

# 设置额外的环境变量以解决显示问题
export NO_AT_BRIDGE=1
export QTWEBENGINE_DISABLE_SANDBOX=1

# 验证X11授权
if [ ! -f "$XAUTHORITY" ]; then
    echo "警告：X11授权文件不存在，创建空授权文件"
    touch "$XAUTHORITY"
    chmod 600 "$XAUTHORITY"
fi

# 测试X11连接
echo "测试X11连接..."
if ! xhost >/dev/null 2>&1; then
    echo "警告：X11连接测试失败，但继续启动Chrome"
fi

# Chrome 启动参数，专门针对VNC环境优化，解决白板问题
# 参考 ubuntu-vnc-xfce-g3 项目的配置
CHROME_ARGS=(
    # 基础安全和沙盒设置
    --no-sandbox
    --disable-setuid-sandbox
    --disable-dev-shm-usage
    
    # GPU和渲染设置（解决白板问题的关键）
    --disable-gpu
    --disable-gpu-sandbox
    --disable-software-rasterizer
    --disable-features=VizDisplayCompositor
    --use-gl=swiftshader-webgl
    --enable-features=UseOzonePlatform
    --ozone-platform=x11
    
    # 禁用可能导致问题的功能
    --disable-extensions
    --disable-plugins
    --disable-web-security
    --disable-features=TranslateUI
    --disable-ipc-flooding-protection
    
    # 性能和稳定性设置
    --no-first-run
    --disable-default-apps
    --disable-infobars
    --disable-background-timer-throttling
    --disable-backgrounding-occluded-windows
    --disable-renderer-backgrounding
    --disable-field-trial-config
    
    # 禁用各种警告和提示（包括 --disable-gpu-sandbox 警告）
    --test-type
    --disable-logging
    --silent-debugger-extension-api
    
    # 调试和数据目录  
    # 注意：--remote-debugging-port 通过命令行参数传入，避免重复配置
    --user-data-dir="$CHROME_USER_DATA_DIR"
    
    # 窗口设置 - 确保最大化启动
    --start-maximized
)

# 查找 Chrome 可执行文件
if command -v google-chrome-stable &> /dev/null; then
    CHROME_EXEC="google-chrome-stable"
elif command -v google-chrome &> /dev/null; then
    CHROME_EXEC="google-chrome"
elif command -v chromium-browser &> /dev/null; then
    CHROME_EXEC="chromium-browser"
elif command -v chromium &> /dev/null; then
    CHROME_EXEC="chromium"
else
    echo "错误：未找到 Chrome 或 Chromium 可执行文件"
    exit 1
fi

echo "正在启动 Chrome: $CHROME_EXEC"
echo "显示设置: DISPLAY=$DISPLAY"
echo "授权文件: XAUTHORITY=$XAUTHORITY"
echo "用户数据目录: $CHROME_USER_DATA_DIR"
echo "使用参数: ${CHROME_ARGS[@]} $@"

# 最后一次检查显示连接
if ! xdpyinfo >/dev/null 2>&1; then
    echo "警告：启动时X服务器连接异常，但继续尝试启动Chrome"
fi

# 自动最大化Chrome窗口的函数
maximize_chrome_window() {
    echo "等待Chrome窗口出现并自动最大化..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        # 等待一秒
        sleep 1
        attempt=$((attempt + 1))
        
        # 尝试使用wmctrl最大化浏览器窗口（Chromium 窗口标题/类名为 "Chromium"）
        if wmctrl -l | grep -i "chrom" > /dev/null 2>&1; then
            echo "找到浏览器窗口，正在最大化..."
            wmctrl -r "Chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || \
            wmctrl -r "chromium" -b add,maximized_vert,maximized_horz 2>/dev/null || \
            wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null

            # 也尝试使用xdotool作为备选方案
            chrome_window_id=$(xdotool search --name "Chromium" 2>/dev/null | head -1)
            if [ -n "$chrome_window_id" ]; then
                echo "使用xdotool最大化窗口 ID: $chrome_window_id"
                xdotool windowstate --add MAXIMIZED_VERT MAXIMIZED_HORZ "$chrome_window_id" 2>/dev/null
            fi
            
            echo "✅ Chrome窗口已最大化"
            return 0
        fi
        
        echo "等待Chrome窗口出现... ($attempt/$max_attempts)"
    done
    
    echo "⚠️ 未能在指定时间内找到Chrome窗口进行最大化"
    return 1
}

# 启动 Chrome
echo "启动Chrome浏览器..."

# 在后台启动Chrome
"$CHROME_EXEC" "${CHROME_ARGS[@]}" "$@" &
CHROME_PID=$!

# 在后台运行窗口最大化功能（不阻塞主进程）
maximize_chrome_window &

# 等待Chrome进程
wait $CHROME_PID