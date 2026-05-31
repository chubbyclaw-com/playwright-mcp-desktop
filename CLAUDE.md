# playwright-mcp-desktop

- This project builds a Docker image: a browser desktop accessible over VNC/noVNC,
  shipping a ready-to-use, headful Playwright MCP server out of the box.
- Stack:
    - Ubuntu Server 24.04 + XFCE
    - TigerVNC
    - noVNC + websockify
    - Chromium (native amd64/arm64; `google-chrome` / `google-chrome-stable` are symlinked to it)
    - `@playwright/mcp` (exposed over SSE/HTTP on port 9999, attached to Chromium via CDP)
    - Supervisor (process manager)
- Dockerfile structure follows the [ubuntu-vnc-xfce-g3](https://github.com/accetto/ubuntu-vnc-xfce-g3) project.
- Ports: `5901` VNC, `6080` noVNC, `9999` Playwright MCP.

## Conventions

- All code, comments, and shell output are in English.
- `README.md` is English (the default); `README.zh-CN.md` is the Chinese translation — keep the two in sync when editing either.
- Keep the Chinese font-family alias keys (`楷体` / `黑体` / `宋体`) in `configs/fonts/99-chinese-fonts.conf`; they are functional fallback mappings, not comments.
