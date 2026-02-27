#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# Claude Code + 5 个 MCP 工具卸载脚本（macOS）
#
# 设计目标：
# 1) 仅卸载 Claude Code 与 MCP 配置
# 2) 不卸载 Homebrew / Node.js / Python / uv 等依赖
# ============================================================

BLUE="\033[1;34m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
info()  { printf "\n${BLUE}[提示]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[完成]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[注意]${NC} %s\n" "$*"; }
err()   { printf "${RED}[错误]${NC} %s\n" "$*"; }

MCP_NAMES=("playwright" "fetch" "filesystem" "memory" "sequential-thinking")

command_exists() { command -v "$1" >/dev/null 2>&1; }

ensure_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    err "本脚本仅支持 macOS。"
    exit 1
  fi
}

remove_mcp_with_claude_cli() {
  if ! command_exists claude; then
    warn "未检测到 claude 命令，跳过 CLI 方式移除 MCP。"
    return
  fi

  info "通过 claude CLI 移除 MCP（用户级 + 当前目录 local/project）..."
  local name
  for name in "${MCP_NAMES[@]}"; do
    claude mcp remove "$name" --scope user >/dev/null 2>&1 || true
    claude mcp remove "$name" --scope local >/dev/null 2>&1 || true
    claude mcp remove "$name" --scope project >/dev/null 2>&1 || true
    claude mcp remove "$name" >/dev/null 2>&1 || true
  done
  ok "CLI 方式 MCP 移除完成（存在即删，不存在则跳过）。"
}

remove_mcp_from_config_json() {
  local cfg="$HOME/.claude.json"
  if [ ! -f "$cfg" ]; then
    warn "~/.claude.json 不存在，跳过配置清理。"
    return
  fi

  info "清理 ~/.claude.json 里的 MCP 配置（用户级 + 所有项目）..."
  python3 - <<'PY'
import json, os

path = os.path.expanduser("~/.claude.json")
targets = {"playwright", "fetch", "filesystem", "memory", "sequential-thinking"}

with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

for name in targets:
    data.get("mcpServers", {}).pop(name, None)

projects = data.get("projects", {})
if isinstance(projects, dict):
    for _, proj in projects.items():
        if isinstance(proj, dict):
            servers = proj.get("mcpServers", {})
            if isinstance(servers, dict):
                for name in targets:
                    servers.pop(name, None)

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print("OK")
PY
  ok "配置文件 MCP 清理完成。"
}

uninstall_claude_cli() {
  info "卸载 Claude Code CLI（不会移除依赖）..."

  if command_exists brew && brew list --cask claude >/dev/null 2>&1; then
    brew uninstall --cask claude || true
  fi

  if command_exists npm; then
    npm uninstall -g @anthropic-ai/claude-code >/dev/null 2>&1 || true
  fi

  # 官方安装脚本常见安装位置（仅删除 claude 命令/目录，不删除依赖）
  rm -f "$HOME/.local/bin/claude" 2>/dev/null || true
  rm -f "$HOME/.npm-global/bin/claude" 2>/dev/null || true
  rm -rf "$HOME/.claude/local" 2>/dev/null || true
  rm -rf "$HOME/.claude/bin" 2>/dev/null || true

  if command_exists claude; then
    warn "检测到 claude 命令仍可用：$(command -v claude)"
    warn "可能是通过其他方式安装，请手动检查该路径。"
  else
    ok "Claude Code CLI 已卸载。"
  fi
}

main() {
  ensure_macos
  remove_mcp_with_claude_cli
  remove_mcp_from_config_json
  uninstall_claude_cli
  echo ""
  ok "卸载完成：已移除 Claude Code 与 5 个 MCP 配置，依赖项保持不变。"
}

main
