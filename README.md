# playwright-mcp-desktop

**English** | [中文](README.zh-CN.md)

> A ready-to-use, **headful** [Playwright MCP](https://github.com/microsoft/playwright-mcp) server running inside a real browser desktop — `docker compose up` and you have an MCP endpoint your AI agent can drive, while you watch every click live in your browser over noVNC.

Unlike the stock headless `@playwright/mcp`, this image gives the browser a full XFCE desktop you can **see and interact with** through VNC / noVNC. Great for debugging agents, demos, captchas/logins that need a human, and any workflow where "watching the agent work" matters.

---

## Features

- 🖥️ **Browser desktop** — Ubuntu 24.04 + XFCE, viewable in your web browser
- 🎭 **Playwright MCP, out of the box** — `@playwright/mcp` exposed over SSE/HTTP on port `9999`
- 👀 **Headful & live** — watch the agent drive a real Chromium via noVNC
- 🌐 **VNC + noVNC** — connect with a VNC client or just a web browser
- ♻️ **Self-healing browser** — a manager process keeps Chromium alive and auto-recovers it
- 🈶 **CJK fonts & color emoji** preinstalled
- 📊 **Supervisor** manages every service; **persistent** home volume

## Stack

| Component                  | Purpose                                           |
| -------------------------- | ------------------------------------------------- |
| Ubuntu Server 24.04 + XFCE | Base OS and desktop environment                   |
| TigerVNC                   | VNC server                                        |
| noVNC + websockify         | Browser-based VNC client                          |
| Chromium                   | The browser the agent drives (native amd64/arm64) |
| `@playwright/mcp`          | The MCP server, attached to Chromium over CDP     |
| Supervisor                 | Process manager                                   |

## Ports

| Port   | Service                   |
| ------ | ------------------------- |
| `5901` | VNC                       |
| `6080` | noVNC (web UI)            |
| `9999` | Playwright MCP (SSE/HTTP) |

---

## Quick start

```bash
docker compose up -d
```

Then open the desktop and wire up your agent:

- **Desktop (web):** http://localhost:6080/vnc.html
- **VNC client:** `localhost:5901`
- **MCP endpoint (SSE):** http://localhost:9999/sse

The default VNC password is `password`. Override it:

```bash
VNC_PASSWORD='your-secret' docker compose up -d
```

Or build & run without Compose:

```bash
docker build -t playwright-mcp-desktop .
docker run -d \
  -p 5901:5901 -p 6080:6080 -p 9999:9999 \
  -e VNC_PASSWORD='your-secret' \
  --name playwright-mcp-desktop \
  playwright-mcp-desktop
```

## Connect your MCP client

The server speaks MCP over **SSE** at `http://localhost:9999/sse` (a streamable-HTTP endpoint is also available at `http://localhost:9999/mcp`).

**Claude Code:**

```bash
claude mcp add --transport sse playwright-desktop http://localhost:9999/sse
```

**Cursor / Windsurf / any client that reads `mcpServers` (SSE):**

```json
{
  "mcpServers": {
    "playwright-desktop": {
      "url": "http://localhost:9999/sse"
    }
  }
}
```

**Clients that only support stdio** (e.g. some Claude Desktop builds) can bridge with [`mcp-remote`](https://www.npmjs.com/package/mcp-remote):

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

Now ask your agent to navigate, click, and fill forms — and watch it happen at http://localhost:6080/vnc.html.

## Configuration

Set these as environment variables (Compose reads `VNC_PASSWORD` from your shell):

| Variable                       | Default                      | Description                                                                                                                                                                                                                                                                                                                        |
| ------------------------------ | ---------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `VNC_PASSWORD`                 | `password`                   | VNC password; empty value disables auth                                                                                                                                                                                                                                                                                            |
| `VNC_RESOLUTION`               | `1280x720`                   | Desktop resolution                                                                                                                                                                                                                                                                                                                 |
| `VNC_COL_DEPTH`                | `24`                         | Color depth                                                                                                                                                                                                                                                                                                                        |
| `VNC_PORT`                     | `5901`                       | VNC port                                                                                                                                                                                                                                                                                                                           |
| `NOVNC_PORT`                   | `6080`                       | noVNC web port                                                                                                                                                                                                                                                                                                                     |
| `PLAYWRIGHT_MCP_PORT`          | `9999`                       | Playwright MCP port                                                                                                                                                                                                                                                                                                                |
| `PLAYWRIGHT_MCP_ALLOWED_HOSTS` | _unset_ → `localhost:<port>` | Comma-separated `Host` header allowlist for the MCP endpoint. Unset preserves `@playwright/mcp`'s built-in default (local-only). Set to your reachable host(s) when serving from non-localhost, e.g. `100.99.99.139:9999,mybox.tail.ts.net:9999`. Use `*` to disable the host check entirely (turns off DNS rebinding protection). |
| `CHROME_USER_DATA_DIR`         | `/root/.chrome-userdata`     | Chrome profile dir (persisted via the `home-data` volume)                                                                                                                                                                                                                                                                          |

The container's `/root` is mounted on a named volume (`home-data`), so the browser profile, logins and cookies persist across restarts.

## How it works

Everything runs under **Supervisor**:

1. **`vnc-server`** — starts TigerVNC + an XFCE session on display `:1`.
2. **`novnc-server`** — serves the noVNC web client on `6080`, proxying to VNC.
3. **`browser-manager`** — launches a single Chromium with a CDP debug port (`9222`), health-checks it every 30s, and auto-restarts it on crash.
4. **`playwright-mcp-gateway`** — runs `@playwright/mcp`, **attaches to the existing Chromium** via `--cdp-endpoint`, and exposes MCP on `9999`.

Because the MCP server attaches to a managed, **visible** browser instead of spawning its own headless one, every action the agent takes is rendered on the desktop you can watch over noVNC.

## Project layout

```
playwright-mcp-desktop/
├── Dockerfile                 # Multi-stage image build
├── docker-compose.yml         # Compose service, ports, volume, healthcheck
├── README.md / README.zh-CN.md
├── configs/
│   ├── browser/               # Chromium init flags
│   ├── desktop/               # XFCE desktop shortcuts
│   ├── fonts/                 # CJK fontconfig snippet
│   ├── vnc/                   # VNC xstartup
│   └── xfce/                  # XFCE channel configs
├── scripts/
│   ├── browser-manager.sh     # Chromium lifecycle + auto-recovery
│   ├── start-chrome.sh        # Chromium launch (VNC-tuned flags)
│   ├── start-novnc.sh         # noVNC launcher
│   ├── start-playwright-mcp.sh# Playwright MCP gateway
│   └── start-vnc.sh           # VNC server + XFCE session
└── supervisor/                # Supervisor program configs
```

## Notes

- Default credentials are for local use. **Set `VNC_PASSWORD`** (and don't expose the ports publicly) before using this anywhere shared.
- Chromium is installed as a native package (via the xtradeb PPA) so the image builds on both `amd64` and `arm64`; `google-chrome` / `google-chrome-stable` are symlinked to it for script compatibility.
- The noVNC web desktop defaults to **remote resizing** (the remote desktop auto-fits your browser window) at the **highest image quality**. Adjust it anytime in the noVNC control panel, or edit `configs/novnc/defaults.json`.

## Credits

Dockerfile structure inspired by [accetto/ubuntu-vnc-xfce-g3](https://github.com/accetto/ubuntu-vnc-xfce-g3). Built on [Playwright MCP](https://github.com/microsoft/playwright-mcp), [noVNC](https://github.com/novnc/noVNC), and [TigerVNC](https://tigervnc.org/).
