# 中文本地化术语表

翻译核心主流程时对照本表，保证各面板译法一致。原则：**通用词译中文；产品/技术专有名词保留英文**（Supacode 用户是开发者，混排英文更符合直觉且避免歧义）。

## 保留英文（不译）

| 英文 | 说明 |
| --- | --- |
| Worktree / Worktrees | Git worktree 专有概念，全应用核心术语，保留 |
| Agent | 编码 agent，产品核心术语，保留 |
| Pane | 界面区域专有称呼，保留（避免与"面板 Panel"混淆） |
| GitHub | 品牌名 |
| Pull Request / PR | 保留 |
| commit | 名词保留（"提交历史"里的动作可用"提交"，独立术语用 commit） |
| diff | 保留（"查看 diff"） |
| Ghostty | 终端内核品牌名 |
| Sparkle | 更新框架品牌名 |
| hook | Claude Code hook 概念，保留 |

## 译中文（通用词）

| 英文 | 中文 |
| --- | --- |
| Settings | 设置 |
| General | 通用 |
| Notifications | 通知 |
| Developer | 开发者 |
| Shortcuts | 快捷键 |
| Scripts | 脚本 |
| Global Scripts | 全局脚本 |
| Updates | 更新 |
| Repository / Repositories | 仓库 |
| Restore Defaults | 恢复默认 |
| Terminal | 终端 |
| Tab | 标签页 |
| Sidebar | 侧边栏 |
| Onboarding | 引导 |
| Language | 语言 |
| Enable | 启用 |
| Disable | 禁用 |
| Not found | 未找到 |
| Not authenticated | 未认证 |
| Error | 错误 |
| Loading | 加载中 |
| Cancel | 取消 |
| Done | 完成 |
| Save | 保存 |
| Delete | 删除 |
| Follow System | 跟随系统 |
| Restart | 重启 |
| Simplified Chinese | 简体中文 |

## 风格约定

- **标点**：中文文案用中文标点（，。：），但代码/命令片段内保持原样。
- **占位符**：`%@` / `%lld` 等格式占位符原样保留，只翻译静态部分（如 `"%@ — Scripts"` → `"%@ — 脚本"`）。
- **省略号**：菜单项的 `...`（如 `Settings...`）译文保留 `…`（如 `设置…`）。
- **中英混排**：英文专有名词与中文之间不额外加空格，遵循条目本身；按钮/标签尽量简短。

## 排除清单（MUST NOT 翻译）

即便被 String Catalog 自动提取，以下条目一律保持英文原样、**不填中文译文**：

- `SupaLogger` 日志字符串
- CLI 参数、子命令名、flag（如 `--worktree`）
- URL、路径、bundle id
- Shell 命令片段（如 `gh auth login`、`gh`、`git`）
- 代码内部标识符、枚举 raw value、accessibility identifier（非 label）
- 测试断言字符串
