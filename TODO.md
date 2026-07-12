## 🔴 紧急+重要

## 🟡 重要不紧急
- [x] 终端内文件引用点击直通 diff viewer：检测 path:line 模式/OSC 8，点击在 History diff viewer 打开（难度低，优先做）— 已在 worktree 分支 `worktree-terminal-file-link` 实现，测试全绿，待手动验证+提交
- [x] Agent 任务清单面板：hook 上报 Claude Code todo 状态，侧边栏 worktree 行下渲染任务进度（基于 #634 会话子行，难度中）
- [ ] 原生 prompt composer：粘贴图片、@ 引用文件补全、多行编辑后注入 pane stdin（难度中）
- [ ] 富文本会话转录面板：监听 ~/.claude/projects/*.jsonl，inspector 原生渲染对话流（markdown/代码高亮/工具调用折叠，依赖上游 #641 surface 抽象，难度中高）

## 🟠 紧急不重要

## 🟢 不紧急不重要
