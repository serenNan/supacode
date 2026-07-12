## ADDED Requirements

### Requirement: Files pane 展示当前 worktree 的文件树
Inspector SHALL 提供一个「Files」pane，展示当前选中 worktree 根目录下的文件与文件夹树。树 SHALL 目录优先、同类按名称（本地化、大小写不敏感）排序，每行 SHALL 显示条目名称与文件/文件夹图标。

#### Scenario: 选中 worktree 后打开 Files pane
- **WHEN** 用户选中一个 worktree 并打开 Files pane
- **THEN** 面板显示该 worktree 根目录的第一层条目，目录排在文件之前，同类按名称排序

#### Scenario: 切换选中的 worktree
- **WHEN** Files pane 可见且用户切换到另一个 worktree
- **THEN** 面板显示新 worktree 的文件树，不残留上一个 worktree 的内容

### Requirement: 目录展开与折叠
目录节点 SHALL 支持展开/折叠，默认全部折叠。树数据加载 SHALL 异步进行，不 SHALL 阻塞 UI；加载期间 SHALL 显示加载态。

#### Scenario: 展开目录
- **WHEN** 用户展开一个目录
- **THEN** 该目录的直接子条目按排序规则显示

#### Scenario: 折叠后再次展开
- **WHEN** 用户折叠一个目录后再次展开
- **THEN** 目录恢复显示其子条目，无需重新加载等待

### Requirement: 过滤 .git 与 gitignored 条目
文件树 SHALL 不显示 `.git` 目录，且 SHALL 不显示被该 worktree 的 gitignore 规则忽略的条目。忽略判定 SHALL 与 git 的行为一致（含嵌套 `.gitignore`、全局 excludes）。不含任何可显示文件的空目录 MAY 不显示。

#### Scenario: 根目录包含 .git 与被忽略目录
- **WHEN** worktree 根目录包含 `.git/`、被 `.gitignore` 忽略的 `node_modules/` 与未被忽略的 `Sources/`
- **THEN** 树中只显示 `Sources/`，不显示 `.git/` 与 `node_modules/`

### Requirement: 文件变化时自动刷新并保持视图状态
当 worktree 内文件发生变化时，Files pane SHALL 自动刷新已加载的目录内容，且刷新 SHALL 保持已展开目录集合与当前选中项（若选中项仍存在）。

#### Scenario: 新文件出现在已展开目录中
- **WHEN** Files pane 可见且某已展开目录中新增了一个文件
- **THEN** 该文件出现在树中对应位置，已展开的目录保持展开

#### Scenario: 选中的文件被删除
- **WHEN** 当前选中的文件在磁盘上被删除并触发刷新
- **THEN** 该条目从树中移除，面板不崩溃且清除失效的选中状态

### Requirement: 点击文件用内置查看器预览
用户激活（单击或选中后回车）一个文件节点时，系统 SHALL 用内置文件查看器以只读方式展示该文件的当前工作区内容。

#### Scenario: 打开文本文件
- **WHEN** 用户在树中激活一个文本文件
- **THEN** 内置查看器展示该文件的当前内容

#### Scenario: 激活目录节点
- **WHEN** 用户激活一个目录节点
- **THEN** 目录展开或折叠，不打开查看器

### Requirement: Files pane 切换入口
工具栏 SHALL 提供 Files pane 切换按钮（带说明用途与快捷键的 tooltip），菜单 SHALL 提供对应命令与快捷键，行为与现有 inspector pane 切换模式一致（再次触发时关闭面板）。

#### Scenario: 通过工具栏按钮切换
- **WHEN** 用户点击工具栏 Files 按钮
- **THEN** Files pane 打开；再次点击则关闭

#### Scenario: 通过菜单命令切换
- **WHEN** 用户触发 Files pane 的菜单命令或快捷键
- **THEN** 效果与点击工具栏按钮一致

### Requirement: 空态与错误态
worktree 根目录为空时 Files pane SHALL 显示空态提示；worktree 路径不存在或不可读时 SHALL 显示错误提示，且不 SHALL 崩溃。

#### Scenario: 空 worktree
- **WHEN** worktree 根目录下没有任何可显示条目
- **THEN** 面板显示空态提示

#### Scenario: worktree 路径不可读
- **WHEN** worktree 目录已被删除或无读取权限
- **THEN** 面板显示错误提示

#### Scenario: 远程 worktree
- **WHEN** 当前选中的 worktree 位于远程主机（无本地磁盘路径）
- **THEN** 面板显示"文件树仅支持本地 worktree"的占位提示，不发起加载
