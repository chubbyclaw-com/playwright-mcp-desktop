# playwright-mcp-desktop

[English](README.md) | **中文**

> 开箱即用的**有头（headful）** [Playwright MCP](https://github.com/microsoft/playwright-mcp) 服务器，运行在一个真实的浏览器桌面里 —— `docker compose up` 即可得到一个 MCP 端点供 AI agent 驱动，同时你能通过 noVNC 在浏览器里**实时看到**它的每一次点击。

与官方无头（headless）的 `@playwright/mcp` 不同，本镜像给浏览器配了一个完整的 XFCE 桌面，你可以通过 VNC / noVNC **看到并直接操作**它。非常适合调试 agent、做演示、处理需要人工介入的验证码/登录，以及任何"想看着 agent 干活"的场景。

---

## 特性

- 🖥️ **浏览器桌面** —— Ubuntu 24.04 + XFCE，可在网页里直接查看
- 🎭 **开箱即用的 Playwright MCP** —— `@playwright/mcp` 通过 SSE/HTTP 暴露在 `9999` 端口
- 👀 **有头 & 实时** —— 通过 noVNC 实时观看 agent 操控真实 Chromium
- 🌐 **VNC + noVNC** —— 用 VNC 客户端或仅用浏览器即可连接
- ♻️ **浏览器自愈** —— 管理进程保活 Chromium 并在崩溃后自动恢复
- 🈶 预装 **中日韩字体与彩色 emoji**
- 📊 **Supervisor** 统一管理所有服务；**持久化** home 卷

## 技术栈

| 组件 | 作用 |
|------|------|
| Ubuntu Server 24.04 + XFCE | 基础系统与桌面环境 |
| TigerVNC | VNC 服务器 |
| noVNC + websockify | 基于浏览器的 VNC 客户端 |
| Chromium | agent 驱动的浏览器（原生 amd64/arm64） |
| `@playwright/mcp` | MCP 服务器，通过 CDP 挂接到 Chromium |
| Supervisor | 进程管理器 |

## 端口

| 端口 | 服务 |
|------|------|
| `5901` | VNC |
| `6080` | noVNC（网页界面） |
| `9999` | Playwright MCP（SSE/HTTP） |

---

## 快速开始

```bash
docker compose up -d
```

然后打开桌面并接入你的 agent：

- **桌面（网页）：** http://localhost:6080/vnc.html
- **VNC 客户端：** `localhost:5901`
- **MCP 端点（SSE）：** http://localhost:9999/sse

默认 VNC 密码为 `password`。可覆盖：

```bash
VNC_PASSWORD='your-secret' docker compose up -d
```

不使用 Compose 时直接构建运行：

```bash
docker build -t playwright-mcp-desktop .
docker run -d \
  -p 5901:5901 -p 6080:6080 -p 9999:9999 \
  -e VNC_PASSWORD='your-secret' \
  --name playwright-mcp-desktop \
  playwright-mcp-desktop
```

## 接入你的 MCP 客户端

服务器通过 **SSE** 提供 MCP，地址为 `http://localhost:9999/sse`（同时也提供 streamable-HTTP 端点 `http://localhost:9999/mcp`）。

**Claude Code：**

```bash
claude mcp add --transport sse playwright-desktop http://localhost:9999/sse
```

**Cursor / Windsurf / 任何读取 `mcpServers` 的客户端（SSE）：**

```json
{
  "mcpServers": {
    "playwright-desktop": {
      "url": "http://localhost:9999/sse"
    }
  }
}
```

**仅支持 stdio 的客户端**（如部分 Claude Desktop 版本）可用 [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) 桥接：

```json
{
  "mcpServers": {
    "playwright-desktop": {
      "command": "npx",
      "args": ["mcp-remote", "http://localhost:9999/sse"]
    }
  }
}
```

之后让 agent 去导航、点击、填表 —— 在 http://localhost:6080/vnc.html 实时观看整个过程。

## 配置

通过环境变量设置（Compose 会从你的 shell 读取 `VNC_PASSWORD`）：

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `VNC_PASSWORD` | `password` | VNC 密码；留空则关闭认证 |
| `VNC_RESOLUTION` | `1280x720` | 桌面分辨率 |
| `VNC_COL_DEPTH` | `24` | 色深 |
| `VNC_PORT` | `5901` | VNC 端口 |
| `NOVNC_PORT` | `6080` | noVNC 网页端口 |
| `PLAYWRIGHT_MCP_PORT` | `9999` | Playwright MCP 端口 |
| `CHROME_USER_DATA_DIR` | `/root/.chrome-userdata` | Chrome 配置目录（通过 `home-data` 卷持久化） |

容器的 `/root` 挂载在命名卷（`home-data`）上，因此浏览器配置、登录态与 cookie 会在重启后保留。

## 工作原理

所有服务都运行在 **Supervisor** 之下：

1. **`vnc-server`** —— 在显示 `:1` 上启动 TigerVNC + XFCE 会话。
2. **`novnc-server`** —— 在 `6080` 提供 noVNC 网页客户端，代理到 VNC。
3. **`browser-manager`** —— 启动单个带 CDP 调试端口（`9222`）的 Chromium，每 30 秒做一次健康检查，崩溃时自动重启。
4. **`playwright-mcp-gateway`** —— 运行 `@playwright/mcp`，通过 `--cdp-endpoint` **挂接到已有的 Chromium**，并在 `9999` 暴露 MCP。

由于 MCP 服务器挂接的是一个被管理的、**可见的**浏览器，而非自己另起一个无头实例，agent 的每一个动作都会渲染在你能通过 noVNC 观看的桌面上。

## 项目结构

```
playwright-mcp-desktop/
├── Dockerfile                 # 多阶段镜像构建
├── docker-compose.yml         # Compose 服务、端口、卷、健康检查
├── README.md / README.zh-CN.md
├── configs/
│   ├── browser/               # Chromium 初始化参数
│   ├── desktop/               # XFCE 桌面快捷方式
│   ├── fonts/                 # 中日韩 fontconfig 片段
│   ├── vnc/                   # VNC xstartup
│   └── xfce/                  # XFCE channel 配置
├── scripts/
│   ├── browser-manager.sh     # Chromium 生命周期 + 自动恢复
│   ├── start-chrome.sh        # Chromium 启动（针对 VNC 调优的参数）
│   ├── start-novnc.sh         # noVNC 启动器
│   ├── start-playwright-mcp.sh# Playwright MCP 网关
│   └── start-vnc.sh           # VNC 服务器 + XFCE 会话
└── supervisor/                # Supervisor 各程序配置
```

## 注意事项

- 默认凭据仅供本地使用。在任何共享环境使用前，**请设置 `VNC_PASSWORD`**（并且不要把端口暴露到公网）。
- Chromium 以原生包形式安装（通过 xtradeb PPA），因此镜像可在 `amd64` 与 `arm64` 上构建；为兼容脚本，`google-chrome` / `google-chrome-stable` 均软链到它。

## 致谢

Dockerfile 结构参考 [accetto/ubuntu-vnc-xfce-g3](https://github.com/accetto/ubuntu-vnc-xfce-g3)。基于 [Playwright MCP](https://github.com/microsoft/playwright-mcp)、[noVNC](https://github.com/novnc/noVNC) 与 [TigerVNC](https://tigervnc.org/) 构建。
