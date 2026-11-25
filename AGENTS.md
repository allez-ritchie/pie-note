# AGENTS.md

本文件面向在本仓库中工作的 AI 编程助手（以及人类协作者）。**开始任何工作前必须先读本文件**；
修改代码、文档或配置后，必须按本文件的 Git 约定及时提交。

---

## 1. 仓库作用

本仓库是 **PieNote** 的客户端源码（**Android + Linux/Windows 桌面**）。PieNote 是一个类似 Obsidian 的
**Markdown 笔记 App**，它本身不存储笔记业务数据，而是作为**离线部署的
[Open Notebook](https://github.com/lfnovo/open-notebook) 服务端的编辑器/浏览器**：

- 后端是局域网/内网自建的 Open Notebook（默认 `http://<host>:5055`），
  App 通过其 REST API 读写**笔记本（notebook）与笔记（note）**；
- 首次启动必须配置**后端 Base URL** 与**访问密码**，配置通过校验后才能进入主界面；
- 以 **Markdown** 作为笔记正文格式，编辑器提供**实时预览 / 源码 / 阅读**三视图
  （参考 Obsidian：默认实时预览，点按段落就地展开该段源码；阅读视图可直接勾选任务列表）；
- 支持笔记本浏览、笔记列表、笔记搜索、Markdown 渲染预览；
- 笔记编辑页有**大纲视图**：按 ATX 标题生成层级大纲，宽窗口是右侧侧栏、窄窗口是底部面板，
  点标题可在实时预览 / 源码 / 阅读三视图里跳转（对应 Obsidian 的 Outline 核心）；
  有子标题的条目带可旋转的折叠箭头，标题栏的「全部折叠 / 全部展开」只保留图标；
- **按可用宽高自适应横竖屏与桌面窗口**：窄屏单栏 + 底部悬浮胶囊工具栏，宽屏侧边导航 +
  「笔记本 / 笔记」双栏，编辑器在宽窗口下阅读视图左右分栏（渲染 + 源码对照）；
- **多标签页工作区**：笔记本、搜索、设置与每篇笔记都是标签页；桌面端是 VSCode / Obsidian
  桌面端风格的顶部标签条，移动端是 Obsidian 移动端风格的悬浮工具栏 + 多标签总览；
- 同一套代码编译 **Android APK** 与 **Linux / Windows 桌面端**；
- 密码只用于生成 `Authorization: Bearer <password>` 请求头，绝不明文落盘；
- **暂不处理 Markdown 中的图片链接**（`![](...)` 按普通文本/占位显示，不做图片加载）。

技术栈：Flutter（Dart 3.x）+ Material 3，`http` 负责网络，`flutter_secure_storage`
（Android Keystore / Linux 系统密钥环 / Windows 凭据管理器）保存密码，`shared_preferences` 保存 Base URL
等非敏感配置，状态管理用 `flutter_riverpod`，Markdown 渲染用 `flutter_markdown_plus`，
直接读 Markdown AST（自定义围栏代码块构建器）用 `markdown`，
选择本地文件上传来源用 `file_selector`。

> 本 App 的定位是**客户端**：不做离线笔记同步/冲突合并，不做本地数据库镜像。
> 打开笔记时从后端拉取最新内容，保存时直接 `PUT` 回后端。

---

## 2. 后端 API 约定（重要）

后端 Open Notebook 的接口定义以运行中实例的 `/openapi.json` 与 `/docs` 为准，
常用只读参考：`http://127.0.0.1:5055/openapi.json`。

### 2.1 鉴权

- 服务端通过环境变量 `OPEN_NOTEBOOK_PASSWORD` 开启密码鉴权，
  `GET /api/auth/status` 返回 `{"auth_enabled": true, "message": "..."}`；
- 所有业务接口需要请求头：**`Authorization: Bearer <password>`**（注意是原始密码本身，
  不是 JWT/token，也不是 Basic 认证）。缺少该头返回 `401 {"detail":"Missing authorization header"}`，
  密码错误返回 `401`；
- 鉴权头由 `data/api_client.dart` 统一注入，业务代码不要各自拼装请求头。

### 2.2 关键端点

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| `GET` | `/api/auth/status` | 探测是否需要密码（无需鉴权） |
| `GET` | `/api/notebooks?archived=false&order_by=updated` | 笔记本列表，含 `note_count` / `source_count` |
| `GET` | `/api/notebooks/{id}` | 笔记本详情 |
| `POST` | `/api/notebooks` | 创建笔记本（`{name, description}`） |
| `PUT` | `/api/notebooks/{id}` | 更新笔记本（`{name?, description?, archived?}`） |
| `DELETE` | `/api/notebooks/{id}?delete_exclusive_sources=false` | 级联删除笔记本及其笔记 |
| `GET` | `/api/notes?notebook_id={id}` | 笔记列表（**不传 `notebook_id` 返回全部**） |
| `GET` | `/api/notes/{id}` | 笔记详情 |
| `POST` | `/api/notes` | 创建笔记（`{title?, content, note_type?, notebook_id?}`） |
| `PUT` | `/api/notes/{id}` | 更新笔记（`{title?, content?, note_type?}`） |
| `DELETE` | `/api/notes/{id}` | 删除笔记 |
| — | 笔记 ↔ 笔记本 | **没有公开接口**：归属只是一条 `artifact` 关系边，`PUT /api/notes/{id}` 不接受 `notebook_id`。客户端「移至笔记本」= 复制到目标笔记本 + 删除原笔记（见 2.5）。 |
| `POST` | `/api/search` | 搜索知识库（`{query, type: text\|vector, limit, notebook_ids?}`） |
| `GET` | `/api/sources?notebook_id={id}&limit=&offset=&sort_by=updated&sort_order=desc` | 来源列表（单页上限 100） |
| `GET` | `/api/sources/{id}` | 来源详情（含 `full_text` 与 `notebooks`） |
| `POST` | `/api/sources` | 新建来源（**multipart/form-data**，见 2.4） |
| `POST` | `/api/sources/{id}/retry` | 重新处理失败 / 卡住的来源 |
| `DELETE` | `/api/sources/{id}` | 删除来源 |
| `GET` | `/api/sources/{id}/status` | 处理状态轮询（`status` + `processing_info.error`） |
| `GET` | `/api/sources/{id}/insights` | 来源洞见列表 |
| `POST` | `/api/notebooks/{nid}/sources/{sid}` / `DELETE` 同路径 | 把已有来源加入 / 移出笔记本 |
| `GET` | `/api/chat/sessions?notebook_id={id}` | 笔记本的对话会话列表 |
| `POST` | `/api/chat/sessions` | 新建会话（`{notebook_id, title?, model_override?}`） |
| `GET` | `/api/chat/sessions/{id}` | 会话详情（`messages` 为 `{id,type,content,timestamp?}`） |
| `PUT` / `DELETE` | `/api/chat/sessions/{id}` | 改标题 / `model_override`；删除会话 |
| `POST` | `/api/chat/context` | 按 `context_config` 构建上下文（返回 `context/token_count/char_count`） |
| `POST` | `/api/chat/execute` | 执行一轮问答（**同步**返回完整消息列表） |
| `GET` | `/api/models` / `/api/models/defaults` | 已注册模型 / 默认模型（对话的「模型覆盖」用） |
| `GET` | `/api/config` / `/health` | 服务版本与健康状态 |

### 2.3 数据形状

- 所有 `id` 都是带类型前缀的字符串，例如 `notebook:oa7txn983isabs4c19j5`、
  `note:w1c1mlfjjkzrxj83u9b1`；**拼接 URL 路径时必须保留前缀**，不要做任何截断或解析。
- 时间字段 `created` / `updated` 是**不带时区后缀的 UTC 字符串**
  （如 `2026-11-18 03:23:19.814849+00:00`），解析时按 UTC 处理再转本地展示。
- `NoteResponse` 的 `title` / `content` / `note_type` 在 schema 上可为 `null`，
  模型必须容忍 `null`（fallback 到空串），否则解析会抛异常。
- `POST /api/search` 返回 `{results: [object], total_count, search_type}`，
  `results` 元素是**未强类型的 object**（不同 `type` 字段形状不同），
  客户端只按已知字段（`note_id`/`id`/`title`/`content`/`notebook_id`/`score`）做宽松解析。
- 来源的「类型」不在 `type` 字段里，而要按 `asset` 判断：
  `asset.url` 非空 → 链接、`asset.file_path` 非空 → 上传文件、都为空 → 文本。
  异步创建（`async_processing=true`）时创建响应里 `asset` / `full_text` 都是 `null`，
  要等处理完成后再拉列表/详情才能拿到真实类型。
- `SourceListResponse` 的 `status` 可能为 `null`（老数据），取值有
  `new` / `queued` / `running` / `completed` / `failed`；失败原因在
  `processing_info.error`（后端已截断到 200 字）。
- 对话的上下文协议由 `context_config` 决定，**字符串按子串匹配**：
  `not in` 跳过、`insights` 取来源短上下文（仅 id/title/insights）、
  `full content` 取长上下文（带正文）。笔记只支持 `full content`。
  这些字符串是与后端共享的协议，改动必须两边同步。
- `POST /api/chat/execute` 返回 `{session_id, messages: [...]}`，`messages` 是**完整历史**
  （不是增量），客户端应整体覆盖本地消息列表；它同时是同步接口，模型生成完才返回。

### 2.4 来源创建（multipart）

`POST /api/sources` 的入参由 FastAPI 的 `Form(...)` + `File(...)` 定义，**只能走
multipart/form-data**（`/api/sources/json` 是只支持文本的 legacy 端点，不要用）：

| 字段 | 说明 |
| --- | --- |
| `type` | `link` / `upload` / `text`（必填） |
| `notebooks` | 笔记本 id 数组的 **JSON 字符串**，例如 `["notebook:abc"]` |
| `title` | 标题（文本来源建议必填；为空时后端用 `Processing...` 占位） |
| `url` / `content` | 链接 / 文本来源的正文输入 |
| `file` | 上传文件（`upload` 类型） |
| `embed` | 是否请求向量化，字符串 `"true"` / `"false"` |
| `delete_source` | 处理完成后是否删除上传文件，默认 `false` |
| `async_processing` | 是否后台处理，字符串 `"true"` / `"false"` |

- 客户端固定 `async_processing=true`：立即返回 `status=new` + `command_id`，
  之后轮询 `/api/sources/{id}/status` 到 `completed` / `failed`；
- `embed=true` 需要后端配置嵌入模型，否则会静默不生成向量（`embedded=false`）。

### 2.5 笔记的「置顶」与「移至笔记本」（客户端实现约定）

这两项在 Open Notebook 1.15.1 的公开 API 上**都没有原生支持**，客户端用如下方式落地，
改动时不要误以为后端有对应字段：

- **置顶**：`NoteResponse` 没有置顶字段，`PUT /api/notes/{id}` 也只接受
  `title/content/note_type`。因此置顶是**本设备偏好**，存在 `shared_preferences`
  （`NotePinStore`，key `notes.pinned`），不写进 Markdown 正文（会破坏块间空白、
  污染正文）。UI 上必须保留「仅本设备」提示，不要让用户误以为跨设备同步。
- **移至笔记本**：笔记归属是 `artifact` 关系边，没有 REST 端点。`NoteRepository.moveNote`
  用「`GET` 取完整正文 → `POST` 到目标笔记本 → `DELETE` 原笔记」实现移动，语义与主流
  笔记产品一致（移动 = 改变唯一归属，不是复制/引用）：
  - **笔记 id 会变化**（`created` 也会重置）。工作区必须把已打开的标签页改绑到新 id
    （`WorkspaceNotifier.rebindNoteId`），否则标签页会指向一条已删除的笔记；
  - 移动前必须先把这篇笔记正在编辑的标签页落盘（`NoteActions._flushDirtyTabs`），
    否则未保存的修改会随删除一起丢失；
  - 删除原笔记失败时会回滚刚创建的副本，失败是安全的；
  - 「目标 = 源列表所在笔记本」时不做任何请求（无法原地移动，只能忽略）。
- **批量操作**：后端没有批量端点，只能是 N 次单条请求；部分失败必须把失败条数
  汇总提示（`NotesStrings.batchPartialFailure`），不能只报成功。
- **删除是硬删除**：没有回收站 / Undo，列表与批量删除都必须二次确认。

---

## 3. 目录结构

| 路径 | 作用 |
| --- | --- |
| `lib/main.dart` | 入口，装载 `ProviderScope` 与根 Widget。 |
| `lib/app.dart` | `PieNoteApp`：根据配置状态决定进入「配置页」还是「主界面」。 |
| `lib/data/api_client.dart` | HTTP 客户端：Base URL 归一化、Bearer 头注入、超时、错误映射（`ApiException`）。 |
| `lib/data/api_models.dart` | `Notebook` / `Note` / `SearchHit` 等不可变模型与 `fromJson`（统一容错 `null`）。 |
| `lib/data/note_repository.dart` | 业务门面：笔记本/笔记/搜索的增删改查，供 provider 调用（含「复制 + 删除」式的 `moveNote`）。 |
| `lib/data/note_actions.dart` | 笔记操作结果类型（重命名 / 移动的返回值）。 |
| `lib/data/note_pin_store.dart` | 置顶笔记的本机存储（后端无置顶字段，只存 `shared_preferences`）。 |
| `lib/data/note_text_edits.dart` | 标题 / 正文首行标题的纯文本编辑（重命名时同步 `# 标题`）。 |
| `lib/state/note_actions.dart` | 列表与编辑器共用的笔记操作：重命名、移至笔记本、置顶、副本、批量删除 / 移动。 |
| `lib/data/config_store.dart` | 配置持久化：`baseUrl` 走 `shared_preferences`，`password` 走 `flutter_secure_storage`。 |
| `lib/state/providers.dart` | Riverpod provider：配置状态、API 客户端、仓库、各列表页的 `AsyncNotifier`。 |
| `lib/ui/setup/setup_screen.dart` | 首次启动配置页：Base URL + 密码 + 连接测试。 |
| `lib/ui/home/home_shell.dart` | 主界面入口，委托给 `workspace_shell.dart`。 |
| `lib/ui/home/workspace_shell.dart` | 多标签工作区外壳：桌面「侧边导航 + 顶部标签条」/ 手机「页面铺满 + 底部悬浮胶囊工具栏」，标签页内容用 `IndexedStack` 保活。 |
| `lib/ui/home/desktop_tab_strip.dart` | 桌面标签条：点击切换、`×` / 中键关闭、右键菜单（关闭其他 / 右侧 / 全部）、新建笔记。 |
| `lib/ui/home/mobile_floating_bar.dart` | 移动端悬浮胶囊工具栏与显隐控制器（上划隐藏、下划显示、点按停下不回显）。 |
| `lib/ui/home/mobile_tab_overview.dart` | 移动端「多标签总览」页：2 列卡片网格，切换 / 关闭 / 新建。 |
| `lib/ui/home/workspace_navigator.dart` | 标签页统一打开入口（一级页面 / 笔记列表 / 笔记 / 草稿）。 |
| `lib/state/workspace.dart` | 工作区状态：`WorkspaceTab` / `WorkspaceState` / `WorkspaceNotifier`（打开、激活、关闭、前进后退、会话绑定）。 |
| `lib/ui/notebooks/` | 笔记本列表与笔记列表页（宽屏时两者合并为左右双栏）；笔记的⋯菜单、多选与批量操作在 `notes_screen.dart`，移动目标选择在 `move_to_notebook_dialog.dart`。 |
| `lib/ui/notes/note_editor_screen.dart` | 笔记编辑页：实时预览 / 源码 / 阅读三视图、大纲跳转、保存（含 Ctrl/Cmd+S）、删除、未保存拦截。 |
| `lib/ui/notes/live_preview_editor.dart` | 实时预览编辑器：渲染态点按段落，该段就地变成无边框源码输入框，失焦自动收起（块级 Live Preview）；`header` 参数把笔记名放进同一个滚动区。 |
| `lib/ui/notes/editor_scroll_tail.dart` | 正文滚动区末尾的「半个视口」留白：三个视图共用的 `EditorScrollTail` 与纯函数 `editorBottomInset`。 |
| `lib/ui/notes/markdown_blocks.dart` | Markdown 源码分块（`MarkdownSourceMap`，可逆拼回原文）与块的偏移量/任务序号。 |
| `lib/ui/notes/markdown_tasks.dart` | 任务列表 `- [ ]` 的定位与勾选改写纯函数（跳过围栏代码块）。 |
| `lib/ui/notes/markdown_view.dart` | Markdown 渲染组件：双链、图片占位、任务复选框回调、围栏代码块交给 `markdown_code_block.dart`。 |
| `lib/ui/notes/markdown_code_block.dart` | 围栏代码块渲染：右上角语言角标 + 点按复制、等宽铺满正文、超宽行内部横向滚动。 |
| `lib/ui/notes/markdown_outline.dart` | 大纲纯函数：ATX 标题解析（跳过围栏代码块）、当前标题定位、按标题分节、父子关系与折叠可见性（`headingHasChildren` / `headingAncestorIndexes` / `visibleOutlineHeadings` / `collapsibleHeadingIndexes`）。 |
| `lib/ui/notes/notes_outline_panel.dart` | 大纲面板：宽窗口右侧侧栏 / 窄窗口底部面板，点标题回调跳转；自带折叠状态（单个标题 + 全部折叠/展开）。 |
| `lib/ui/notes/markdown_toolbar.dart` / `markdown_actions.dart` | Markdown 快捷工具条及其纯文本编辑操作（源码/段落共用）。 |
| `lib/ui/search/search_screen.dart` | 全文/向量搜索页。 |
| `lib/ui/sources/` | 来源页：列表（状态胶囊 / 轮询）、添加来源对话框（链接 / 文本 / 文件）、详情（正文 + 洞见）。 |
| `lib/ui/chat/` | 「与笔记本对话」：会话管理、上下文勾选、模型覆盖、消息流与「保存为笔记」。 |
| `lib/ui/settings/settings_screen.dart` | 后端地址、密码、连接测试、退出配置。 |
| `lib/ui/common/` | 通用组件（加载/错误/空状态、确认对话框）、响应式断点 `layout.dart`、平台判定 `app_platform.dart`。 |
| `lib/ui/theme/` | Material 3 主题（浅色/深色、动态取色）。 |
| `linux/` | Linux 桌面端工程（Flutter 生成，窗口标题/默认尺寸在 `runner/my_application.cc`）。 |
| `windows/` | Windows 桌面端工程（Flutter 生成，窗口标题/默认尺寸/最小尺寸在 `runner/main.cpp` 与 `runner/win32_window.*`）。 |
| `scripts/setup_linux_deps.sh` | Linux 桌面端构建依赖准备（libsecret 开发文件 / clang 链接器 shim）。 |
| `scripts/build_linux.sh` / `scripts/build_windows.ps1` | 桌面端一键构建脚本（依赖准备 → 构建 → 打印/归档产物）。 |
| `scripts/generate_app_icons.py` | 由 `assets/branding/app_icon.svg` 重新生成 Android mipmap / adaptive icon、Windows `.ico` 与图标 PNG。 |
| `test/` | JVM/Dart 单元测试（模型解析、URL 归一化、鉴权头、错误映射、响应式断点）。 |
| `assets/branding/` | 应用图标：`app_icon.svg` 是唯一设计源，`app_icon.png` 供桌面窗口图标与配置页 Logo 使用。 |

**共享文件**（见 5.1）之外的模块文案集中在 `lib/ui/common/` 与各页自身；界面文案统一走
`lib/ui/common/strings.dart`，禁止在各页面里散落硬编码文案。

---

## 4. 构建、测试与验证

环境要求：Flutter 3.4x（Dart 3.11+）、Android SDK 36、JDK 21、`ANDROID_HOME` 已配置。
桌面端按目标平台二选一：

- **Linux**：`clang`、`cmake`、`ninja`、`pkg-config`、GTK3 开发包、`libsecret-1-dev`（见 4.2）；
- **Windows**：Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载（MSVC v143 +
  Windows 10/11 SDK）；`cmake` / `ninja` 由 VS 自带，`flutter doctor` 能识别即可（见 4.3）。

常用命令：

```bash
# 拉取依赖
flutter pub get

# 静态分析（门禁，不允许 error）
flutter analyze

# 单元测试
flutter test

# 打包 Debug APK（产物 build/app/outputs/flutter-apk/app-debug.apk）
flutter build apk --debug

# 打包 Linux 桌面端（产物 build/linux/x64/release/bundle/pie_note）
eval "$(scripts/setup_linux_deps.sh --print-env)"
flutter build linux --release
```

```powershell
# 打包 Windows 桌面端（产物 build/windows/x64/runner/Release/pie_note.exe）
pwsh -File scripts/build_windows.ps1              # release
pwsh -File scripts/build_windows.ps1 -DebugBuild   # debug
pwsh -File scripts/build_windows.ps1 -Bundle       # 额外归档 dist/pie-note-windows-x64-<mode>.zip
```

补充说明：

- Pub 使用国内镜像（`https://pub.flutter-io.cn`），首次 `pub get` 需要联网；
  依赖版本一旦确定请提交 `pubspec.lock`（本仓库为 App 工程，锁定版本更稳）。
- 不能提交无法编译的代码，也不能提交 `build/` 产物、`.dart_tool/`、
  `android/local.properties`、签名文件与任何密码/令牌。
- 提交前至少保证 `flutter analyze` 无 error 且 `flutter test` 通过；
  涉及 UI/依赖/Manifest 的改动再跑 `flutter build apk --debug`。
- `minSdk 24`、`targetSdk 36`、`compileSdk 36`；明文 HTTP（局域网自建后端）通过
  `network_security_config.xml` 显式放行，**不要**直接全局打开 `usesCleartextTraffic`。
- Android 9+ 默认禁止明文 HTTP，且模拟器访问宿主机需要 `10.0.2.2` 或 `adb reverse`；
  调试网络相关改动时优先用 `adb reverse tcp:5055 tcp:5055` 把后端映射进模拟器。

### 4.1 响应式布局（横竖屏 / 桌面）约定

页面**不读 `MediaQuery.orientation`**，一律按可用宽高分支（`lib/ui/common/layout.dart`）：

| 断点 | 条件 | 行为 |
| --- | --- | --- |
| 侧边导航 + 标签条 | 宽 >= 720 | `NavigationRail` + 顶部标签条 |
| 双栏列表 | 宽 >= 840 且高 >= 480 | 笔记本页左列表、右笔记，点击不跳页 |
| 编辑器分栏 | 宽 >= 900 且高 >= 420 | 阅读视图左右分栏（渲染 + Markdown 源码） |
| 大纲侧栏 | 宽 >= 1080 且高 >= 420 | 编辑器右侧常驻大纲侧栏；更窄时点标题栏的目录图标弹底部面板 |

多标签的形态同样只按宽度切换（不读 orientation）：

| 宽度 | 形态 |
| --- | --- |
| 宽 >= 720（桌面 / 平板横屏 / 手机横屏） | `NavigationRail` + 顶部标签条（参考 VSCode / Obsidian 桌面端） |
| 窄 < 720（手机竖屏、窄桌面窗口） | 页面铺满 + 底部悬浮胶囊工具栏（参考 Obsidian 移动端），标签总览为 2 列卡片页 |

多标签约定（改这块代码前必读）：

- **状态在 `lib/state/workspace.dart`**：页面不要自己 `Navigator.push` 编辑器，一律走
  `WorkspaceNavigator`；同一条笔记已打开时切到原标签页，不重复创建。
- **页面保活靠 `IndexedStack`**：编辑草稿、列表滚动位置、搜索词在切标签时都不丢。
  标签页内容只在首次激活时才真正构建（`_visited`），避免一次打开多个编辑器并发拉正文。
- **未保存拦截统一在工作区**：编辑页实现 `WorkspaceTabSession`（`isDirty` / `save` /
  `discardChanges`），关闭标签页（× / `Ctrl+W` / 标签总览关闭）时由外壳弹一次确认。
  编辑页**不要**在 `initState` / `dispose` 里写 provider 状态（会命中
  「Tried to modify a provider while the widget tree was building」），会话注册放到
  `addPostFrameCallback`，注销由 `WorkspaceNotifier.closeTab` 负责。
- **桌面快捷键走 `HardwareKeyboard` 全局监听**：`Ctrl/Cmd + W` 关闭、`+T` 新建、
  `+Tab` / `+Shift+Tab` 循环、`+1..9` 跳到第 N 个标签页。不要改用
  `CallbackShortcuts`：切换标签后焦点可能留在离屏页面上，Focus 树里的快捷键会失效。
- **移动端悬浮工具栏显隐只由滚动方向驱动**：`ScrollUpdateNotification.scrollDelta`
  为正隐藏、为负显示，`ScrollEndNotification` 不改变状态 —— 这样在惯性滚动中点按屏幕
  停下不会让工具栏回显。正文底部要给胶囊留出约 84 的空白（`_floatingBarInset`），
  手机端也不要再放右下角 FAB（会与胶囊重叠），新建入口放到标题栏或胶囊的「+」。

- 高度断点是必须的：手机横屏通常只有 400~450 高，只按宽度判定会把列表挤成两条细缝。
- 宽窗口下页面内容用 `ContentFrame` 限宽居中，避免超长行；
- 桌面快捷键：编辑器内 `Ctrl/Cmd + S` 保存（`CallbackShortcuts`），保存按钮 tooltip 随平台显示 `Ctrl` / `⌘`。
- 新增页面时请复用 `Responsive` / `ContentFrame`，不要再写魔法数字。

### 4.2 Linux 桌面端构建

- 工程目录 `linux/`（`flutter create --platforms=linux` 生成，已纳入版本管理）。
- 密码存储走 `flutter_secure_storage` 的 Linux 实现，**编译期**需要 `libsecret-1` 的
  开发文件、**运行期**需要系统密钥环（Secret Service）：
  - Debian/Ubuntu：`sudo apt install libsecret-1-dev`（Fedora：`libsecret-devel`；Arch：`libsecret`）；
  - 没有 root 时执行 `scripts/setup_linux_deps.sh --local`：把 .deb 里的头文件 / `.pc` /
    `.so` 链接解到 `.desktop-deps/`（已忽略），不改动系统目录。
- 该脚本同时会生成 `.desktop-deps/toolchain`（`clang++` 包装脚本 + `ld`/`llvm-ar` 软链）：
  Flutter 的 native assets 编译会用 `clang++` 所在目录找链接器，Ubuntu 的 clang-18 默认
  **不带 lld**，不补这一步 `flutter build linux` 会报
  `Failed to find any of [ld.lld, ld] in LocalDirectory: '/usr/lib/llvm-18/bin'`。
- 构建前统一：`eval "$(scripts/setup_linux_deps.sh --print-env)"`（会 export
  `PKG_CONFIG_PATH` / `LIBRARY_PATH` / `PATH`）。
- 桌面端没有可用的系统密钥环时，保存配置会失败并提示「无法写入系统密钥环（libsecret）」，
  **不会**退化成明文存储（见 `SecretStorageException`）。

### 4.3 Windows 桌面端构建

- 工程目录 `windows/`（`flutter create --platforms=windows` 生成，已纳入版本管理）。
- 前置：Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载（MSVC v143 + Windows 10/11 SDK）。
  `cmake` / `ninja` 用 VS 自带的即可（`flutter doctor -v` 的 Visual Studio 一项应为 ✓）；
- 密码存储走 `flutter_secure_storage` 的 Windows 实现（系统凭据管理器），
  不需要额外开发包，也没有 Linux 那套 libsecret / 链接器 shim 的问题；
- 一键构建：`pwsh -File scripts/build_windows.ps1`（`-DebugBuild` / `-Bundle` 见脚本头注释）。
  产物 `build/windows/x64/runner/Release/pie_note.exe`，需连同同目录的 `data/` 与 `*.dll` 一起分发；
- 窗口外观对齐 Linux：标题 `PieNote`、默认 1180x820、最小 420x560
  （`windows/runner/main.cpp` 与 `win32_window.*` 的 `WM_GETMINMAXINFO`）。

**坑点**：runner 的 C++ 源码里是中文注释，MSVC 在中文代码页（936）下会报 C4819，
而 `apply_standard_settings` 开了 `/WX`（警告即错误）。因此 `windows/runner/CMakeLists.txt`
必须保留 `target_compile_options(${BINARY_NAME} PRIVATE "/utf-8")`，删掉就会构建失败。

### 4.4 手工/模拟器端到端验证

1. 确认本机后端可用：`curl -s http://127.0.0.1:5055/health` 返回 `{"status":"healthy"}`；
   取密码：`docker exec open-notebook printenv OPEN_NOTEBOOK_PASSWORD`。
2. 映射端口：`adb reverse tcp:5055 tcp:5055`（模拟器无外网时 `10.0.2.2` 可能不可用）。
3. 安装并启动：`adb install -r build/app/outputs/flutter-apk/app-debug.apk`，
   App 内 Base URL 填 `http://127.0.0.1:5055`、密码填上一步的值，
   点「测试连接」应显示服务版本，保存后进入主界面。
4. 验证点：笔记本列表应显示后端已有笔记本及其笔记数量；进入笔记本能看到笔记列表；
   打开笔记正文渲染 Markdown 标题/代码块/列表正常；编辑并保存后
   `curl -H "Authorization: Bearer <pw>" http://127.0.0.1:5055/api/notes/<id>` 内容已更新；
   搜索页输入关键词能命中后端笔记；`settings` 里改密码为错误值后测试连接应失败并提示。
5. 实时预览验证点：打开含标题/任务列表/代码块/引用的笔记，默认应以渲染态展示；
   点按某一段落，仅该段就地变成**无边框、无「完成」按钮**的源码输入框（其余仍渲染），
   工具条可插入 Markdown；点按别处（失焦）即自动收起并还原渲染；
   光标在本段行首时按 `Backspace` 应删掉段前空行、上一段整段展开成源码、
   光标落在上一行行尾，再按一次退格能删掉上一行的最后一个字；
   把整段文字删空后输入框不能消失（焦点不能丢），此时继续退格仍要能接上上一段；
   点任务复选框应立即勾选并标为「未保存」；
   保存后用 `curl` 核对后端正文只改动了目标区域、块间空行未被打乱；
   保存成功的提示应是顶部半透明小横幅（不遮住底部编辑区、不拦截点击、自动消失）。
   实时预览不再有「点按任意段落即可就地编辑…」这行提示；
   笔记名（标题 + 保存状态行）与正文在同一个滚动区，滚到底时应完全滚出视口；
   围栏代码块右上有语言角标（`python` / `text` 等），点角标或点整块复制源码，
   角标就地变「已复制」；实时预览里点代码块主体应展开该段源码（不是复制）；
   同一篇里两段代码块宽度一致（短块不会缩成半截）。
   正文末尾（三视图都一样）应留出约**半个视口**的空白：把笔记拖到最底部时，
   最后一行要能继续上滚到屏幕中间，而不是永远贴着页面下缘（参考 Obsidian）；
   短笔记不应因此凭空出现一大段可滚动留白（内容不足一屏时仍贴顶显示）。
6. 横竖屏验证点：模拟器旋转（或改窗口尺寸）后不应出现溢出条纹；
   竖屏是页面铺满 + 底部悬浮胶囊工具栏 + 单栏，点进笔记本打开新的笔记列表标签页；
   横屏（宽 >= 720）改为侧边导航 + 顶部标签条，宽 >= 840 且高 >= 480 时笔记本与笔记并排；
   编辑器在宽且高的窗口里阅读视图分栏。
7. 大纲验证点：打开含多个 `#` / `##` 标题的笔记，点 AppBar 的目录图标；
   宽窗口右侧出现大纲侧栏（窄窗口是底部面板），列出 H1/H2 层级；点「第二章」后
   实时预览 / 源码 / 阅读三种视图都应滚动到该标题（源码视图光标落在标题文字上）；
   源码视图把光标移到别的标题后，大纲高亮跟着变；代码块里的 `# 注释` 不出现在大纲里。
   有子标题的条目左侧有「›」，点击只折叠它的子标题（兄弟标题不受影响），折叠后箭头转为朝下 /朝右；
   标题栏的「全部折叠 / 全部展开」应在两种状态之间切换；扁平（无子标题）笔记不显示这两个按钮。
   把光标移进被折叠的子标题时，其上级会自动展开，保证高亮项始终可见。
   再点一次目录图标（或侧栏的关闭按钮）收起侧栏。
8. 选区验证点：阅读视图长按并拖动，应能跨段落、跨标题小节连续选中（选区高亮不断开），
   复制得到整段文字；工具条选中多行后点 H1/H2/列表/引用，应逐行加前缀，
   再点一次逐行移除；实时预览点按段落仍进入就地编辑（不被选区手势抢走）。
   桌面端实时预览**按住鼠标左键向上（或向下）跨行拖动**：拖出就地输入框后，相邻段落会
   并入同一个编辑框，选区从按下点连续覆盖到指针处，复制得到包含 `**加粗**` 等标记的
   Markdown 源码，而不是只有点击的那一行；松手后编辑框保持展开、点按别处收起，
   整篇正文不会被重复写入。反向拖回去时已并入的段落不丢（合并范围只增不减）。
9. 多标签验证点：桌面点笔记开新标签、再次点击已有笔记只切换；`Ctrl/Cmd + W` 关闭、
   `+T` 新建、`+Tab` 循环、`+1..9` 跳转；关闭未保存标签会弹「保存并关闭 / 不保存 / 取消」；
   手机端点胶囊的标签图标进入 2 列卡片总览，可切换 / 关闭 / 新建；
   长笔记上划时胶囊自动隐藏，惯性滚动中点按屏幕停下**不应**回显，下划才显示。
10. 笔记操作验证点：笔记列表的⋯菜单应有「重命名 / 移至笔记本 / 置顶 / 创建副本 / 删除」；
   重命名后正文首行的 `# 标题` 同步改写、其余正文不变；置顶后该笔记置顶到「置顶」分组、
   重启 App 仍在（本机偏好）；「移至笔记本」后原笔记本列表里消失、目标笔记本里出现，
   且已打开的笔记标签页仍指向新的笔记 id；多选（长按行 / 标题栏「选择」）后可用
   全选 / 反选 / 底部批量条（置顶 / 移至 / 复制 / 删除），部分失败有汇总提示。
11. 桌面端验证点：`flutter build linux --release` / `flutter build windows --release` 产物可直接运行；
   宽窗口下双栏/侧边栏生效，把窗口拖窄到 420 附近自动退回悬浮工具栏 + 单栏；
   编辑器 `Ctrl+S` 保存成功并提示（Windows 上悬浮工具栏/双栏断点与 Linux 完全一致，
   因为两边都只读 Flutter 的可用宽高）。

---

## 5. 多 AI 会话协作与交接方式

同一工作目录下可能有多个 AI 会话（Lead 与若干 teammate）并行工作，**共享同一个文件系统**，
彼此的修改立即可见。遵循以下约定可避免互相覆盖和重复劳动：

### 5.1 分工与写入边界

- 按**垂直切片**拆分任务（一个功能从数据到 UI 端到端交给一个负责人），而不是按“层”拆分。
- 每个任务都要在共享任务板登记**写入范围（write scopes）**；只能修改自己范围内的文件。
- 以下**共享文件**默认只由 Lead（或任务指定的唯一负责人）修改，其他会话不要直接改：
  `pubspec.yaml`、`android/app/src/main/AndroidManifest.xml`、
  `android/app/build.gradle.kts`、`lib/main.dart`、`lib/app.dart`、
  `lib/ui/common/strings.dart`、`lib/state/providers.dart`、`lib/ui/theme/` 下的主题文件。
  功能模块的文案请先在自己的文件里写好，评审时由负责人合并进 `strings.dart`。
- 需要改共享文件时，通过消息/任务说明需求，由负责人统一修改，避免并发编辑冲突。
- 文件操作报 `FS_STALE_VERSION` 时：重新读取最新内容，在最新内容上重做改动，不要强推旧版本。

### 5.2 交接记录（Handoff）

每次会话结束、切换负责人或遇到阻塞时，在 `.agents/handoff/` 下写交接文件：

```
.agents/handoff/<yyyy-MM-dd>-<任务 slug>.md
```

必须包含：目标与背景、当前状态（已完成 / 进行中 / 未开始）、改动文件清单与关键设计决策、
待办事项（可执行到文件与函数级别）、验证命令与最近一次结果、风险与坑点。

- **`.agents/handoff/` 下的交接文档只保留在本地，不提交到 git**：它们是会话间的临时工作状态，
  不是仓库产物。该目录已在 `.gitignore` 中忽略，仅 `README.md`（模板）保留跟踪。
- 因此**不要为 handoff 文档单独提交**；`git status` / `git add` 时应确认没有混入
  `.agents/handoff/` 下的文件。
- 需要长期留存的结论（设计决策、接口约定、迁移方式）请固化到 `AGENTS.md`、`README.md`、
  其他正式文档或代码注释中，而不是依赖 handoff。

**新会话接续工作时的顺序**：读 `AGENTS.md` → 读相关 handoff 文件（本地文件，不在 git 历史中）
→ `git status` / `git log --oneline -10` → 再开始动手。

### 5.3 验证与提交责任

- 并行开发期间，**各会话不要自行执行 `git commit` / `git push`**，避免共享索引与历史冲突。
- 由 Lead（或任务指定的唯一集成负责人）在功能完成、编译通过、必要测试通过后统一提交。
- 提交前必须 `git status` 检查改动是否都属于当前提交范围，确认没有混入他人未完成的修改。
- Lead 给出最终答复前，必须完成最终 diff 审查并跑通最终验证。

---

## 6. Git 提交规范（强制）

### 6.1 语言要求

- **提交信息必须使用中文**（`type`、`scope` 可以保留英文约定，描述、正文必须中文）。
- 禁止使用 `update`、`fix`、`修改`、`提交` 这类无信息量的提交信息。

### 6.2 提交时机

- **更新文档、修复 bug、添加新功能后必须及时提交**，完成一项提交一项。
- 不要把多个不相关改动塞进同一个提交；也不要攒很久再一次性提交。
- 提交前必须保证改动可编译；不得提交半成品或无法通过编译的代码。

### 6.3 Conventional Commits

格式：

```
<type>(<scope>): <中文简短描述>

<可选中文正文：说明动机、方案、影响面>

<可选脚注：BREAKING CHANGE / Closes #123 等>
```

常用 `type`：`feat` / `fix` / `docs` / `style` / `refactor` / `perf` / `test` /
`build` / `ci` / `chore` / `revert`。

示例：

```
feat(notes): 支持笔记编辑与 Markdown 预览切换
fix(auth): 修复密码错误时未提示而静默失败的问题
docs(agents): 补充模拟器端到端验证步骤
build(android): 放行局域网明文 HTTP 后端地址
```

其他要求：

- 一个提交只做一件事，提交信息与改动内容必须一致；
- 不提交密钥、账号密码、`local.properties`、签名文件、APK/AAB 产物、IDE 临时文件；
- 不提交 `.agents/handoff/` 下的交接文档（仅模板保留跟踪），详见 5.2 节；
- 破坏性变更使用 `!` 标注（如 `feat(api)!: ...`）并在正文说明迁移方式。

---

## 7. 代码与安全约定（摘要）

### 7.1 网络与鉴权

- 所有请求必须经 `data/api_client.dart`，统一处理 Base URL 归一化（补 `http://`、
  去尾部 `/`）、`Authorization: Bearer` 头、超时（连接/读取分开设置）与错误映射。
- 密码**只能**存放在 `flutter_secure_storage`（Android Keystore / Linux 系统密钥环 /
  Windows 凭据管理器），
  不得写入 `shared_preferences`、日志、异常消息、UI 明文展示（输入框用 `obscureText`）。
- 安全存储写入失败必须**报错并中止保存**（`ConfigStore.save` 抛 `SecretStorageException`），
  不允许为了「能存就行」降级成明文；`ConfigStore.save` 先写密码再写 Base URL。
- 日志/错误提示中**禁止**输出密码与完整请求头；`ApiException` 只保留状态码与后端 `detail`。
- 自建后端多为 HTTP 明文：仅通过 `network_security_config.xml` 按需放行，
  不要图省事全局 `usesCleartextTraffic="true"`（`usersCleartextTrafficPermitted` 需保留说明）。
- Base URL 校验必须拒绝空值与非 `http/https` scheme；局域网地址允许纯 IP + 端口。

### 7.2 状态与线程

- 网络与 IO 一律异步（`async/await`），禁止在主 isolate 做同步阻塞调用。
- 页面状态用 Riverpod `AsyncNotifier`/`AsyncValue` 表达 `loading / data / error` 三态，
  **不要**在 `StatefulWidget` 里手写 `isLoading` 布尔与业务数据字段。
- 编辑中的笔记草稿只在内存保存；离开页面前若有未保存改动必须拦截确认，
  避免误丢内容。保存失败时保留草稿并提示重试，不要清空编辑器。
- 编辑器三视图共用同一个 `TextEditingController`：实时预览的就地编辑必须写回整篇正文，
  因此**不要**在分块/组件里另存整篇副本；改写正文的路径（勾选复选框、段落提交、
  切视图）都要走 `MarkdownSourceMap` / `MarkdownTasks` 的偏移量，避免破坏块间空白。

### 7.3 UI

- 所有用户可见文案集中在 `lib/ui/common/strings.dart`，禁止在各页面硬编码文案。
- 组件拆分为可复用的小 Widget，避免单个文件堆到上千行；配色统一走
  `lib/ui/theme/` 下的 `ColorScheme`，不要散落硬编码颜色值。
- 列表用 `ListView.builder` + 稳定 `key`；长文本用 `maxLines` + `overflow` 控制溢出。
- Markdown 渲染必须容忍不规范文本（未闭合代码块、超长行、`![]()` 图片语法），
  图片语法按普通文本处理（本仓库**不实现**图片加载）。
- 危险操作（删除笔记本/笔记）必须二次确认；删除笔记本前提示会连带删除其笔记。

### 7.4 依赖与构建

- 新增依赖必须先在 `pubspec.yaml` 里明确版本，并在本文件第 1 节技术栈中登记用途。
- 平台相关文案（「Android Keystore」「手机」等）不要硬编码在页面里，统一走
  `lib/ui/common/app_platform.dart`（`AppPlatform.secretStorageName` / `deviceNoun` / `shortcutKeyLabel`）。
- 不引入重量级本地数据库/同步框架；本 App 无本地笔记存储，后端是唯一数据源。
- `android/app/src/debug/` 下的测试辅助代码不得影响 release 构建。

---

## 8. 已知边界（非 bug）

- **不做图片处理**：Markdown 中的 `![](path)` 不加载、不上传，按文本显示。
- **代码块不做语法高亮**：只按等宽字体渲染（颜色统一走主题），不引入高亮依赖；
  代码块也不折叠，超长代码块随正文滚动，超宽行在代码块内部横向滚动。
- **大纲只认 ATX 标题**（`# 标题`）：Setext 标题（`===` / `---` 下划线）不进大纲，
  且跳转是「滚动到标题」而不是 Markdown 锚点链接。
- **不做离线编辑**：断网时列表与笔记读取失败会提示错误，不提供本地缓存兜底。
- **不做冲突合并**：同一笔记被多处同时修改时，后保存的覆盖先保存的。
- **AI 能力全部由后端承担**：本 App 只调用 Open Notebook 的
  `/api/chat/*`（笔记本对话）与 `/api/sources/*`（来源处理 / 洞见 / 向量化），
  不内置任何模型配置、密钥或本地推理；模型选择只是把 `model_override`
  （`model:<id>`）透传给后端，后端未注册模型或额度不足时把错误原样提示给用户。
- **对话不是流式**：后端 `/api/chat/execute` 同步返回完整回答，
  客户端只能在等待期间显示「AI 正在回答…」，没有逐字输出。
- **桌面端做 Linux 与 Windows**：`linux/` 与 `windows/` 两个平台工程都已纳入版本管理，
  并各自在对应系统上验证过 release 构建；**macOS 未承诺**，需要时在 Mac 上
  `flutter create --platforms=macos .` 后自行验证。
