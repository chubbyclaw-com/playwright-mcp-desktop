# MCP Desktop 项目

基于Ubuntu 24.04构建的桌面环境，支持通过VNC访问，集成Google Chrome浏览器和Playwright MCP工具。

## 功能特性

- 🖥️ Ubuntu 24.04 + XFCE桌面环境
- 🌐 VNC + noVNC Web访问
- 🏄 Google Chrome浏览器
- 🎭 Playwright MCP工具，支持SSE
- 📊 Supervisor进程管理
- 💾 持久化数据存储

## 端口服务

- **5901**: VNC端口
- **6080**: noVNC Web界面
- **9999**: Playwright MCP API + SSE

## 快速开始

### 构建和启动

```bash
# 使用Docker Compose启动
docker-compose up -d

# 或者手动构建
docker build -t mcp-desktop .
docker run -d -p 5901:5901 -p 6080:6080 -p 9999:9999 mcp-desktop
```

### 访问方式

1. **Web界面**: http://localhost:6080 (noVNC)
2. **VNC客户端**: localhost:5901
3. **MCP API**: http://localhost:9999
4. **SSE事件流**: http://localhost:9999/sse

### 测试MCP功能

```bash
# 测试SSE连接
curl -N http://localhost:9999/sse

# 发送MCP消息
curl -X POST http://localhost:9999/message \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}'
```

## 目录结构

```
mcp-desktop/
├── Dockerfile                    # 主要的Docker构建文件
├── docker-compose.yml           # Docker Compose配置
├── README.md                    # 项目说明文件
├── configs/                     # 配置文件目录
│   ├── browser/                 # 浏览器相关配置
│   │   └── google-chrome.init   # Chrome初始化配置
│   ├── desktop/                 # 桌面快捷方式配置
│   │   ├── google-chrome.desktop # Chrome桌面快捷方式
│   │   └── terminal.desktop     # 终端桌面快捷方式
│   ├── system/                  # 系统级配置
│   │   └── disable-login1.conf  # D-Bus登录服务禁用配置
│   ├── vnc/                     # VNC相关配置
│   │   └── xstartup            # VNC启动脚本
│   └── xfce/                    # XFCE桌面环境配置
│       ├── xfce4-desktop.xml    # XFCE桌面配置
│       └── xfce4-settings-manager.xml # XFCE设置管理器配置

├── scripts/                     # 启动脚本目录
│   ├── start-chrome.sh         # Chrome启动脚本

│   ├── start-novnc.sh          # noVNC启动脚本
│   ├── start-playwright-mcp.sh # Playwright MCP启动脚本
│   └── start-vnc.sh            # VNC服务器启动脚本
├── supervisor/                  # Supervisor进程管理配置
│   ├── supervisord.conf        # Supervisor主配置文件

│   ├── novnc.conf             # noVNC服务配置
│   ├── playwright-mcp.conf     # Playwright MCP服务配置
│   └── vnc.conf               # VNC服务配置
└── ubuntu-vnc-xfce-g3/         # 第三方VNC-XFCE项目参考
```

## 结构说明

### 🗂️ configs/ - 配置文件目录
统一存放各种配置文件，按功能分类：
- **browser/**: 浏览器配置（Chrome等）
- **desktop/**: 桌面快捷方式配置
- **system/**: 系统级配置（D-Bus、服务等）
- **vnc/**: VNC服务器配置
- **xfce/**: XFCE桌面环境配置

### 📜 scripts/ - 脚本目录
存放各种启动和管理脚本：
- **start-chrome.sh**: Chrome浏览器启动脚本，包含WSL兼容性设置

- **start-novnc.sh**: noVNC Web客户端启动脚本
- **start-vnc.sh**: VNC服务器启动脚本

### 👮 supervisor/ - 进程管理配置
存放Supervisor进程管理器的所有配置文件：
- **supervisord.conf**: 主配置文件

- **novnc.conf**: noVNC服务进程配置
- **vnc.conf**: VNC服务进程配置

## 优势

### 📁 清晰的文件组织
- 相关文件按功能分组
- 易于查找和维护
- 减少根目录文件混乱

### 🔧 配置文件独立
- 所有配置文件从Dockerfile中提取出来
- 可以独立编辑和版本控制
- 便于调试和自定义

### 🏗️ 构建优化
- 使用COPY指令替代内联创建
- 更好的Docker构建缓存利用
- 减少Dockerfile复杂度

### 🛠️ 维护便利
- 修改配置无需编辑Dockerfile
- 配置变更可独立测试
- 更容易的故障排查

## 使用方法

构建Docker镜像：
```bash
docker build -t mcp-desktop .
```

使用docker-compose启动：
```bash
docker-compose up -d
```

访问桌面环境：
- VNC: `localhost:5901`
- noVNC (Web): `http://localhost:6080`

## 注意事项

1. 确保所有脚本文件具有执行权限
2. 配置文件路径在Dockerfile中正确引用
3. 修改配置后需要重新构建镜像
4. 保持文件编码为UTF-8，特别是包含中文的配置文件
