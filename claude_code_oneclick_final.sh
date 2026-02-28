#!/usr/bin/env bash
set -eo pipefail

# ============================================================
# Claude Code（官方 CLI）+ 5 个 MCP 工具一键安装脚本（macOS）
#
# 安装内容：
#   【运行时依赖】
#   - Homebrew   - macOS 包管理器
#   - Node.js    - JavaScript 运行时（通过 Homebrew 安装）
#   - Python 3   - Python 运行时（通过 uv 安装，官方推荐方式）
#   - uv / uvx   - Python 工具链（Anthropic 官方推荐）
#
#   【MCP 工具】（全部来自 Anthropic 官方 modelcontextprotocol 仓库）
#   1. playwright          - 控制浏览器：截图、填表、自动化网页操作
#                            启动方式：npx（TypeScript 服务器，官方推荐）
#   2. fetch               - 抓取任意网页内容给 Claude 阅读
#                            启动方式：uvx（Python 服务器，官方推荐）
#   3. filesystem          - 读写本地文件（授权目录：桌面 + 下载）
#                            启动方式：npx（TypeScript 服务器，官方推荐）
#   4. memory              - 跨会话持久记忆，Claude 能记住你的偏好
#                            启动方式：npx（TypeScript 服务器，官方推荐）
#   5. sequential-thinking - 结构化思维拆解，帮助分析复杂问题
#                            启动方式：npx（TypeScript 服务器，官方推荐）
#
# ✅ 适合：全新 macOS 设备，无需预装任何工具
# ✅ 兼容：Apple Silicon（M 系列）和 Intel 两种 Mac
# ✅ 最低系统要求：macOS 13 Ventura
#
# ⚠️  唯一需要手动操作：Xcode CLT 弹窗时点"安装"，装完重新运行本脚本
# 本脚本可重复执行，不会重复安装已有内容
#
# 退出码说明：
#   1  - 非 macOS 系统 / brew 找不到
#   2  - 等待用户安装 Xcode CLT，请装完后重新运行
#   3  - Node 或 uvx 安装后仍不可用（含诊断信息）
#   4  - Claude CLI 安装后不可用，请重开终端再试
#   5  - 找不到 node/npx/uvx 绝对路径
#   7  - 最终检查失败，请重开终端再试
#   8  - macOS 版本过低
#   9  - Homebrew 安装失败
# ============================================================

BLUE="\033[1;34m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; RED="\033[1;31m"; NC="\033[0m"
info()  { printf "\n${BLUE}[提示]${NC} %s\n" "$*"; }
ok()    { printf "${GREEN}[完成]${NC} %s\n" "$*"; }
warn()  { printf "${YELLOW}[注意]${NC} %s\n" "$*"; }
err()   { printf "${RED}[错误]${NC} %s\n" "$*"; }

step=0
next_step() {
  step=$((step+1))
  printf "\n${BLUE}========== 第 %d 步 ==========${NC}\n" "$step"
  info "$1"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# ── PATH 工具 ──────────────────────────────────────────────────────────────

ensure_block_in_file() {
  local file="$1"
  local marker_start="$2"
  local line="$3"
  local marker_end="$4"
  [ -f "$file" ] || touch "$file"
  if ! grep -qF "$marker_start" "$file" 2>/dev/null; then
    printf '\n%s\n%s\n%s\n' "$marker_start" "$line" "$marker_end" >> "$file"
    return 0
  fi
  return 1
}

all_shell_rc_files=(
  "$HOME/.zprofile"
  "$HOME/.zshrc"
  "$HOME/.bash_profile"
  "$HOME/.bashrc"
)

inject_brew_shellenv() {
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  for brew_bin in "/opt/homebrew/bin" "/opt/homebrew/sbin" "/usr/local/bin" "/usr/local/sbin"; do
    if [[ -d "$brew_bin" ]] && [[ ":${PATH}:" != *":${brew_bin}:"* ]]; then
      export PATH="${brew_bin}:${PATH}"
    fi
  done
  hash -r 2>/dev/null || true
}

# 注入 uv 安装路径（~/.local/bin 或 ~/.cargo/bin，取决于安装方式）
inject_uv_path() {
  for uv_bin in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    if [[ -d "$uv_bin" ]] && [[ ":${PATH}:" != *":${uv_bin}:"* ]]; then
      export PATH="${uv_bin}:${PATH}"
    fi
  done
  hash -r 2>/dev/null || true
}

find_node_absolute() {
  local p
  for p in "/opt/homebrew/bin/node" "/usr/local/bin/node" "/usr/bin/node"; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

find_npx_absolute() {
  local p
  for p in "/opt/homebrew/bin/npx" "/usr/local/bin/npx" "/usr/bin/npx"; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

find_uvx_absolute() {
  local p
  for p in "$HOME/.local/bin/uvx" "$HOME/.cargo/bin/uvx" "/opt/homebrew/bin/uvx" "/usr/local/bin/uvx"; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

find_python_absolute() {
  local p
  # 优先找 uv 管理的 python，再找系统 python3
  for p in "$HOME/.local/bin/python3" "/opt/homebrew/bin/python3" "/usr/local/bin/python3" "/usr/bin/python3"; do
    if [[ -x "$p" ]]; then echo "$p"; return 0; fi
  done
  return 1
}

# ── 重试工具 ───────────────────────────────────────────────────────────────

retry() {
  local times="$1"; shift
  local sleep_s="$1"; shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$times" ]; then
      err "已达最大重试次数（${times}），命令最终失败：$*"
      return 1
    fi
    warn "命令失败，${sleep_s}s 后重试（${n}/${times}）：$*"
    sleep "$sleep_s"
    n=$((n+1))
  done
}

# ── MCP 注册工具 ────────────────────────────────────────────────────────────

mcp_exists() {
  local name="$1"
  if [ ! -f "$HOME/.claude.json" ]; then return 1; fi
  CLAUDE_CHECK_NAME="$name" python3 - <<'PY'
import json, os, sys
path = os.path.expanduser("~/.claude.json")
name = os.environ.get("CLAUDE_CHECK_NAME", "")
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    servers = data.get("mcpServers", {})
    sys.exit(0 if name in servers else 1)
except Exception:
    sys.exit(1)
PY
}

# 注册用 npx 启动的 MCP（用户级，全局）
# 用法: register_npx_mcp <名称> <npm包> <npx绝对路径> [额外参数...]
register_npx_mcp() {
  local name="$1"
  local pkg="$2"
  local npx_abs="$3"
  shift 3

  if mcp_exists "$name"; then
    warn "${name}（用户级）MCP 已存在，先移除再重新注册..."
    claude mcp remove "$name" --scope user 2>/dev/null || claude mcp remove "$name" 2>/dev/null || true
  fi

  info "注册 ${name}（用户级）：${npx_abs} -y ${pkg} $*"
  if [ $# -gt 0 ]; then
    claude mcp add "$name" --scope user -- "$npx_abs" -y "$pkg" "$@"
  else
    claude mcp add "$name" --scope user -- "$npx_abs" -y "$pkg"
  fi
  ok "${name} MCP 注册完成。"
}

# 注册用 uvx 启动的 MCP（用户级，全局）
# 用法: register_uvx_mcp <名称> <PyPI包名> <uvx绝对路径>
register_uvx_mcp() {
  local name="$1"
  local pkg="$2"
  local uvx_abs="$3"

  if mcp_exists "$name"; then
    warn "${name}（用户级）MCP 已存在，先移除再重新注册..."
    claude mcp remove "$name" --scope user 2>/dev/null || claude mcp remove "$name" 2>/dev/null || true
  fi

  info "注册 ${name}（用户级）：${uvx_abs} ${pkg}"
  claude mcp add "$name" --scope user -- "$uvx_abs" "$pkg"
  ok "${name} MCP 注册完成。"
}

# ── 各安装步骤 ─────────────────────────────────────────────────────────────

ensure_macos() {
  if [ "$(uname -s)" != "Darwin" ]; then
    err "本脚本仅支持 macOS。"
    exit 1
  fi
}

check_macos_version() {
  next_step "检查 macOS 版本（Homebrew 要求 macOS 13 Ventura 或更新）"
  local full_ver
  local major_ver
  full_ver="$(sw_vers -productVersion)"
  major_ver="$(echo "$full_ver" | cut -d'.' -f1)"
  info "当前 macOS 版本：$full_ver"
  if [ "$major_ver" -lt 13 ]; then
    err "你的 macOS 版本（$full_ver）过低。"
    err "Homebrew 要求 macOS 13 Ventura 或更新，请先升级系统后再运行本脚本。"
    err "升级方式：苹果菜单 → 系统设置 → 通用 → 软件更新"
    exit 8
  fi
  ok "macOS 版本检查通过：$full_ver（>= 13 Ventura）"
}

check_network_reasonable() {
  next_step "检查网络（只验证安装真正需要的下载源）"
  local ok_count=0
  local url
  for url in "https://claude.ai/install.sh" "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"; do
    info "测试：$url"
    if curl -sSIL --ipv4 --connect-timeout 5 --max-time 15 --retry 2 --retry-delay 1 "$url" >/dev/null 2>&1; then
      ok "可访问：$url"
      ok_count=$((ok_count+1))
    else
      warn "访问失败：$url（可能是 DNS/代理/网络策略）"
    fi
  done
  if [ "$ok_count" -ge 1 ]; then
    ok "网络检查通过。"
  else
    warn "网络检查未通过，后续下载大概率会失败。建议先检查代理设置 / DNS。"
  fi
  if env | grep -iE '^(http_proxy|https_proxy|all_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY)=' >/dev/null 2>&1; then
    warn "检测到代理环境变量，如下载失败请检查代理是否正常。"
    warn "临时关闭代理：unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy"
  fi
}

ensure_xcode_clt() {
  next_step "检查 Xcode Command Line Tools（必需）"
  if xcode-select -p >/dev/null 2>&1; then
    ok "Xcode CLI 已安装：$(xcode-select -p)"
    return
  fi
  warn "未检测到 Xcode Command Line Tools，macOS 会弹出安装窗口，请手动点"安装"。"
  warn "安装完成后请重新运行本脚本。"
  xcode-select --install >/dev/null 2>&1 || true
  exit 2
}

_run_brew_install() {
  local install_script
  install_script="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh 2>&1)" || {
    err "下载 Homebrew 安装脚本失败，请检查网络。"
    return 1
  }
  /bin/bash -c "$install_script"
}

ensure_brew() {
  next_step "检查并安装 Homebrew"
  inject_brew_shellenv
  if command_exists brew; then
    ok "Homebrew 已安装：$(brew --version | head -n 1)"
  else
    warn "未检测到 Homebrew，开始安装（需要输入密码）..."
    if ! retry 3 5 _run_brew_install; then
      err "Homebrew 安装失败。请检查网络后重新运行，或访问 https://brew.sh 手动安装。"
      exit 9
    fi
    ok "Homebrew 安装完成。"
    inject_brew_shellenv
  fi
  if ! command_exists brew; then
    err "找不到 brew，请关闭终端重开后再运行脚本。"
    exit 1
  fi
  ok "brew 可用：$(command -v brew)"
}

persist_brew_shellenv() {
  next_step "确保 Homebrew PATH 永久生效"
  local shellenv_cmd
  if [[ -x "/opt/homebrew/bin/brew" ]]; then
    shellenv_cmd='eval "$(/opt/homebrew/bin/brew shellenv)"'
  else
    shellenv_cmd='eval "$(/usr/local/bin/brew shellenv)"'
  fi
  local marker="# >>> brew shellenv（claude_code_oneclick_final.sh 自动添加）"
  local marker_end="# <<< brew shellenv"
  local f
  for f in "${all_shell_rc_files[@]}"; do
    if ensure_block_in_file "$f" "$marker" "$shellenv_cmd" "$marker_end"; then
      info "写入 Homebrew PATH 到：$f"
    else
      info "Homebrew PATH 已存在，跳过：$f"
    fi
  done
  ok "Homebrew PATH 已写入 shell 配置文件。"
  info "更新 Homebrew 索引..."
  retry 3 5 brew update
  ok "Homebrew 已更新。"
}

ensure_node() {
  next_step "安装 Node.js（playwright / filesystem / memory / sequential-thinking 依赖）"
  inject_brew_shellenv
  local node_abs
  local npx_abs
  node_abs="$(find_node_absolute || true)"
  npx_abs="$(find_npx_absolute || true)"
  if [ -n "$node_abs" ] && [ -n "$npx_abs" ]; then
    ok "Node 已就绪：$node_abs（$("$node_abs" -v)）"
    ok "npx 已就绪：$npx_abs"
    return
  fi
  warn "未在标准路径找到 node/npx，开始通过 Homebrew 安装..."
  if brew list --formula node >/dev/null 2>&1; then
    info "node 有安装记录但找不到二进制，尝试修复..."
    brew unlink node 2>/dev/null || true
    retry 2 3 brew upgrade node
    brew link --overwrite --force node 2>/dev/null \
      || brew link --overwrite node 2>/dev/null \
      || true
  else
    retry 3 5 brew install node
  fi
  inject_brew_shellenv
  node_abs="$(find_node_absolute || true)"
  npx_abs="$(find_npx_absolute || true)"
  if [ -n "$node_abs" ] && [ -n "$npx_abs" ]; then
    ok "Node 安装完成：$node_abs（$("$node_abs" -v)）"
    ok "npx 可用：$npx_abs"
  else
    info "【诊断】Cellar/node："
    ls -la /opt/homebrew/Cellar/node/ 2>/dev/null || ls -la /usr/local/Cellar/node/ 2>/dev/null || echo "找不到"
    info "【诊断】/opt/homebrew/bin/ 中 node/npx："
    ls -la /opt/homebrew/bin/node* /opt/homebrew/bin/npx* 2>/dev/null || echo "无"
    err "Node 安装后仍找不到，请截图诊断信息后手动执行：brew unlink node && brew link node"
    exit 3
  fi
}

ensure_uv_and_python() {
  next_step "安装 uv + Python 3（fetch MCP 依赖；Python 对日常脚本工作也很有用）"

  inject_uv_path

  # ── 1. 安装 uv ────────────────────────────────────────────────────────────
  if find_uvx_absolute >/dev/null 2>&1; then
    ok "uvx 已就绪：$(find_uvx_absolute)"
  else
    warn "未检测到 uv，开始安装（官方安装脚本：astral.sh/uv）..."
    # 安全提示：这是 uv 官方安装地址，Anthropic 官方 Python 工具链推荐
    retry 3 5 bash -c 'curl -fsSL https://astral.sh/uv/install.sh | bash'
    inject_uv_path

    if find_uvx_absolute >/dev/null 2>&1; then
      ok "uv 安装完成：$(find_uvx_absolute)"
    else
      err "uv 安装后仍找不到 uvx，请关闭终端重开后再运行脚本。"
      exit 3
    fi
  fi

  # ── 2. 通过 uv 安装 Python 3（官方推荐方式）─────────────────────────────
  # uv 自带 Python 管理能力，比 Homebrew 装 python 更轻量、不影响系统 Python
  local uvx_abs
  uvx_abs="$(find_uvx_absolute)"
  local uv_bin
  uv_bin="$(dirname "$uvx_abs")/uv"

  if find_python_absolute >/dev/null 2>&1; then
    ok "Python 3 已就绪：$(find_python_absolute)（$($(find_python_absolute) --version)）"
  else
    info "通过 uv 安装 Python 3（最新稳定版）..."
    "$uv_bin" python install 3.12
    inject_uv_path
    # uv 安装的 python 在 ~/.local/share/uv/python/*/bin/python3，
    # 通过 uv run python / uvx 可以直接用，不需要加到 PATH
    ok "Python 3 已通过 uv 安装完成。"
  fi

  # 验证 python3 可用（脚本内部 mcp_exists 等 heredoc 需要用到）
  if ! command_exists python3; then
    # uv 安装的 python 不在系统 PATH，但 macOS Xcode CLT 自带 python3，通常足够
    # 如果连系统 python3 都没有，提示用户
    warn "系统 python3 不在 PATH 中，尝试通过 uv 创建一个可用链接..."
    "$uv_bin" tool install python 2>/dev/null || true
    inject_uv_path
  fi

  if command_exists python3; then
    ok "python3 命令可用：$(python3 --version)"
  else
    err "python3 不在 PATH 中，脚本内部依赖 python3 处理配置文件。请关闭终端重开后再试。"
    exit 3
  fi

  # 无论 uv 是否刚安装，都确保 ~/.local/bin 在 bash/zsh 都会生效（claude 默认装在这里）。
  local uv_marker="# >>> local bin PATH（claude_code_oneclick_final.sh 自动添加）"
  local uv_line='export PATH="$HOME/.local/bin:$PATH"'
  local uv_end="# <<< local bin PATH"
  local f
  info "确保 ~/.local/bin 对 bash 和 zsh 永久生效..."
  for f in "${all_shell_rc_files[@]}"; do
    if ensure_block_in_file "$f" "$uv_marker" "$uv_line" "$uv_end"; then
      info "写入 local bin PATH 到：$f"
    fi
  done
}

install_or_update_claude() {
  next_step "安装/更新 Claude Code 官方 CLI"
  if command_exists claude; then
    info "检测到 Claude：$(claude --version)"
    claude update || true
    ok "Claude 更新完成。"
  else
    warn "未检测到 claude，开始安装..."
    retry 3 5 bash -c 'curl -fsSL https://claude.ai/install.sh | bash'
    ok "Claude 安装完成。"
  fi
  inject_brew_shellenv
  inject_uv_path
  hash -r 2>/dev/null || true
  if command_exists claude; then
    ok "Claude 版本：$(claude --version)"
  else
    err "安装后仍找不到 claude，请关闭终端重开后再试：claude --version"
    exit 4
  fi
}

install_all_mcp() {
  next_step "安装 5 个 MCP 工具（用户级，全局可用）"

  local NODE_ABS
  local NPX_ABS
  local UVX_ABS
  NODE_ABS="$(find_node_absolute 2>/dev/null || command -v node 2>/dev/null || true)"
  NPX_ABS="$(find_npx_absolute 2>/dev/null || command -v npx 2>/dev/null || true)"
  UVX_ABS="$(find_uvx_absolute 2>/dev/null || command -v uvx 2>/dev/null || true)"

  if [ -z "$NODE_ABS" ] || [ -z "$NPX_ABS" ]; then
    err "找不到 node/npx 绝对路径，请先确认 Node 安装成功。"
    exit 5
  fi
  if [ -z "$UVX_ABS" ]; then
    err "找不到 uvx 绝对路径，请先确认 uv 安装成功。"
    exit 5
  fi

  ok "MCP 安装范围：用户级（跨项目可用）"
  ok "node    ：$NODE_ABS（$("$NODE_ABS" -v)）"
  ok "npx     ：$NPX_ABS"
  ok "uvx     ：$UVX_ABS"

  # ── 1. Playwright ── TypeScript 服务器，官方推荐 npx ──────────────────────
  info "── [1/5] Playwright（npx）：控制浏览器，截图、填表、自动化网页操作 ──"
  register_npx_mcp "playwright" "@playwright/mcp@latest" "$NPX_ABS"

  # ── 2. Fetch ── Python 服务器，官方推荐 uvx ───────────────────────────────
  info "── [2/5] Fetch（uvx）：抓取任意网页内容给 Claude 阅读 ──"
  register_uvx_mcp "fetch" "mcp-server-fetch" "$UVX_ABS"

  # ── 3. Filesystem ── TypeScript 服务器，官方推荐 npx ─────────────────────
  # 授权桌面和下载目录，PM 日常最常用的两个位置
  info "── [3/5] Filesystem（npx）：读写本地文件（桌面 + 下载） ──"
  register_npx_mcp "filesystem" "@modelcontextprotocol/server-filesystem" \
    "$NPX_ABS" "$HOME/Desktop" "$HOME/Downloads"

  # ── 4. Memory ── TypeScript 服务器，官方推荐 npx ─────────────────────────
  info "── [4/5] Memory（npx）：跨会话持久记忆，Claude 能记住你的偏好和背景 ──"
  register_npx_mcp "memory" "@modelcontextprotocol/server-memory" "$NPX_ABS"

  # ── 5. Sequential Thinking ── TypeScript 服务器，官方推荐 npx ────────────
  info "── [5/5] Sequential Thinking（npx）：结构化思维拆解，分析复杂问题 ──"
  register_npx_mcp "sequential-thinking" "@modelcontextprotocol/server-sequential-thinking" \
    "$NPX_ABS"

  ok "5 个 MCP 工具全部注册完成。"
  info "当前 MCP 列表："
  claude mcp list || true
}

final_check_and_next() {
  next_step "最终检查与使用指引"
  inject_brew_shellenv
  inject_uv_path
  hash -r 2>/dev/null || true

  local all_ok=true

  if command_exists claude; then
    ok "Claude CLI   ：$(claude --version)"
  else
    err "Claude CLI 不可用。"; all_ok=false
  fi

  local node_abs
  node_abs="$(find_node_absolute || true)"
  if [ -n "$node_abs" ]; then
    ok "Node         ：$node_abs（$("$node_abs" -v)）"
  else
    err "Node 不可用。"; all_ok=false
  fi

  local npx_abs
  npx_abs="$(find_npx_absolute || true)"
  if [ -n "$npx_abs" ]; then
    ok "npx          ：$npx_abs"
  else
    err "npx 不可用。"; all_ok=false
  fi

  local uvx_abs
  uvx_abs="$(find_uvx_absolute || true)"
  if [ -n "$uvx_abs" ]; then
    ok "uvx          ：$uvx_abs"
  else
    err "uvx 不可用。"; all_ok=false
  fi

  if command_exists python3; then
    ok "Python 3     ：$(python3 --version)"
  else
    warn "python3 暂不在 PATH 中，可重开终端后运行 python3 --version 验证。"
  fi

  # 检查新开的登录 shell 是否也能找到 claude，避免脚本内可用但用户终端不可用。
  if /bin/bash -lc 'command -v claude >/dev/null 2>&1'; then
    ok "bash 登录环境：claude 可用"
  else
    warn "bash 登录环境：暂时找不到 claude"
  fi
  if /bin/zsh -lc 'command -v claude >/dev/null 2>&1'; then
    ok "zsh 登录环境：claude 可用"
  else
    warn "zsh 登录环境：暂时找不到 claude"
  fi

  if [ "$all_ok" = "false" ]; then
    err "部分工具不可用，请关闭终端重新打开后再运行本脚本。"
    exit 7
  fi

  echo ""
  echo "🎉 安装完成！"
  echo ""
  echo "已安装的工具："
  echo "  • Node.js   $(node -v 2>/dev/null || echo '(重开终端可用)')"
  echo "  • Python 3  $(python3 --version 2>/dev/null || echo '(重开终端可用)')"
  echo "  • uv/uvx    $(uvx --version 2>/dev/null | head -1 || echo '(重开终端可用)')"
  echo ""
  echo "已就绪的 MCP 工具："
  echo "  1. playwright          → 控制浏览器，截图、填表、自动化网页操作"
  echo "  2. fetch               → 抓取任意网页内容给 Claude 阅读"
  echo "  3. filesystem          → 读写桌面和下载文件夹里的文件"
  echo "  4. memory              → 跨会话记忆（记住你的偏好和项目背景）"
  echo "  5. sequential-thinking → 结构化思维拆解，分析复杂问题"
  echo ""
  echo "第一次使用请先登录（会打开浏览器）："
  echo "  claude auth login"
  echo ""
  echo "然后在任意目录启动 Claude Code："
  echo "  claude"
  echo ""
  echo "启动后输入 /mcp 可查看所有 MCP 工具状态。"
  echo ""
  echo "如果当前终端提示 claude: command not found，请执行："
  echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
  echo "  hash -r"
  echo "或重载 shell 配置："
  echo "  bash: source ~/.bash_profile"
  echo "  zsh : source ~/.zprofile"
  ok "搞定，享受 Claude Code 吧！"
}

main() {
  ensure_macos
  check_macos_version
  check_network_reasonable
  ensure_xcode_clt
  ensure_brew
  persist_brew_shellenv
  ensure_node
  ensure_uv_and_python
  install_or_update_claude
  install_all_mcp
  final_check_and_next
}

main
