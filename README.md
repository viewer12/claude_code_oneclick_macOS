# Claude Code 一键安装脚本（macOS）

一键安装 Claude Code 官方 CLI + 5 个实用 MCP 工具的自动化脚本，适用于 macOS 系统。

## 🎯 功能特性

### 自动安装的工具

**运行时依赖：**
- **Homebrew** - macOS 包管理器
- **Node.js** - JavaScript 运行时（通过 Homebrew 安装）
- **Python 3** - Python 运行时（通过 uv 安装，官方推荐方式）
- **uv / uvx** - Python 工具链（Anthropic 官方推荐）

**MCP 工具（全部来自 Anthropic 官方 modelcontextprotocol 仓库）：**
1. **playwright** - 控制浏览器：截图、填表、自动化网页操作
2. **fetch** - 抓取任意网页内容给 Claude 阅读
3. **filesystem** - 读写本地文件（授权目录：桌面 + 下载）
4. **memory** - 跨会话持久记忆，Claude 能记住你的偏好
5. **sequential-thinking** - 结构化思维拆解，帮助分析复杂问题

**MCP 安装范围：**
- **用户级（全局）**：安装后在任意项目、任意终端启动 Claude Code 都可用

## ✅ 系统要求

- **操作系统**：macOS 13 Ventura 或更新版本
- **架构**：支持 Apple Silicon（M 系列）和 Intel Mac
- **网络**：需要稳定的网络连接以下载依赖

## 🚀 使用方法

### 1. 下载脚本

```bash
curl -fsSL https://raw.githubusercontent.com/viewer12/claude_code_oneclick_macOS/main/claude_code_oneclick_final.sh -o claude_code_oneclick_final.sh
```

### 2. 添加执行权限

```bash
chmod +x claude_code_oneclick_final.sh
```

### 3. 运行脚本

```bash
./claude_code_oneclick_final.sh
```

### 4. 首次使用

安装完成后，需要先登录 Claude：

```bash
claude auth login
```

然后在任意目录启动 Claude Code：

```bash
claude
```

启动后输入 `/mcp` 可查看所有 MCP 工具状态。

## 🗑️ 卸载方法（仅卸载 Claude Code + MCP）

本仓库提供卸载脚本：`claude_code_oneclick_uninstall.sh`

```bash
chmod +x claude_code_oneclick_uninstall.sh
./claude_code_oneclick_uninstall.sh
```

说明：
- 会移除 Claude Code CLI
- 会移除 5 个 MCP（用户级和项目级配置）
- **不会**卸载 Homebrew / Node.js / Python / uv 等依赖

## ⚠️ 注意事项

- **Xcode Command Line Tools**：首次运行时，macOS 会弹出安装窗口，请点击"安装"。安装完成后重新运行本脚本。
- **Homebrew 安装**：安装 Homebrew 时需要输入管理员密码。
- **可重复执行**：本脚本可以重复执行，不会重复安装已有内容。
- **网络要求**：脚本会从官方源下载工具，请确保网络连接稳定。

## 🔧 故障排除

### 退出码说明

- `1` - 非 macOS 系统 / brew 找不到
- `2` - 等待用户安装 Xcode CLT，请装完后重新运行
- `3` - Node 或 uvx 安装后仍不可用（含诊断信息）
- `4` - Claude CLI 安装后不可用，请重开终端再试
- `5` - 找不到 node/npx/uvx 绝对路径
- `7` - 最终检查失败，请重开终端再试
- `8` - macOS 版本过低
- `9` - Homebrew 安装失败

### 常见问题

**Q: 安装失败怎么办？**
A: 大部分情况下，关闭终端重新打开后再运行脚本即可解决。

**Q: 网络连接失败？**
A: 检查代理设置或 DNS 配置。如果使用代理，确保代理正常工作。

**Q: 如何卸载？**
A: 可以使用 Homebrew 卸载相关工具：
```bash
brew uninstall node
brew uninstall --cask claude
```

## 📝 许可证

本项目采用 [MIT License](LICENSE) 开源。

## 🙏 致谢

- [Anthropic](https://www.anthropic.com/) - Claude Code 和 MCP 工具
- [Homebrew](https://brew.sh/) - macOS 包管理器
- [Astral](https://astral.sh/) - uv Python 工具链

## 📮 反馈与贡献

如有问题或建议，欢迎提交 [Issue](https://github.com/viewer12/claude_code_oneclick_macOS/issues)。
