# AGENTS.md

本文件面向在本仓库中工作的 AI 编程助手（以及人类协作者）。**开始任何工作前必须先读本文件**；
修改代码、文档或配置后，必须按本文件的 Git 约定及时提交。

---

## 1. 仓库作用

本仓库是 **PieNote** 的 Android 客户端源码。PieNote 是一个类似 Obsidian 的
**Markdown 笔记 App**，它本身不存储笔记业务数据，而是作为**离线部署的
[Open Notebook](https://github.com/lfnovo/open-notebook) 服务端的移动端编辑器/浏览器**：

- 后端是局域网/内网自建的 Open Notebook（默认 `http://<host>:5055`），
  App 通过其 REST API 读写**笔记本（notebook）与笔记（note）**；
- 首次启动必须配置**后端 Base URL** 与**访问密码**，配置通过校验后才能进入主界面；
- 以 **Markdown** 作为笔记正文格式，编辑器提供**实时预览 / 源码 / 阅读**三视图
  （参考 Obsidian：默认实时预览，点按段落就地展开该段源码；阅读视图可直接勾选任务列表）；
- 支持笔记本浏览、笔记列表、笔记搜索、Markdown 渲染预览；
- 密码只用于生成 `Authorization: Bearer <password>` 请求头，绝不明文落盘；
- **暂不处理 Markdown 中的图片链接**（`![](...)` 按普通文本/占位显示，不做图片加载）。

技术栈：Flutter（Dart 3.x）+ Material 3，`http` 负责网络，`flutter_secure_storage`
（Android Keystore）保存密码，`shared_preferences` 保存 Base URL 等非敏感配置，
状态管理用 `flutter_riverpod`，Markdown 渲染用 `flutter_markdown_plus`。

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
| `POST` | `/api/search` | 搜索知识库（`{query, type: text\|vector, limit, notebook_ids?}`） |
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

---

## 3. 目录结构

| 路径 | 作用 |
| --- | --- |
| `lib/main.dart` | 入口，装载 `ProviderScope` 与根 Widget。 |
| `lib/app.dart` | `PieNoteApp`：根据配置状态决定进入「配置页」还是「主界面」。 |
| `lib/data/api_client.dart` | HTTP 客户端：Base URL 归一化、Bearer 头注入、超时、错误映射（`ApiException`）。 |
| `lib/data/api_models.dart` | `Notebook` / `Note` / `SearchHit` 等不可变模型与 `fromJson`（统一容错 `null`）。 |
| `lib/data/note_repository.dart` | 业务门面：笔记本/笔记/搜索的增删改查，供 provider 调用。 |
| `lib/data/config_store.dart` | 配置持久化：`baseUrl` 走 `shared_preferences`，`password` 走 `flutter_secure_storage`。 |
| `lib/state/providers.dart` | Riverpod provider：配置状态、API 客户端、仓库、各列表页的 `AsyncNotifier`。 |
| `lib/ui/setup/setup_screen.dart` | 首次启动配置页：Base URL + 密码 + 连接测试。 |
| `lib/ui/home/home_shell.dart` | 主界面骨架（底部导航：笔记本 / 最近 / 搜索 / 设置）。 |
| `lib/ui/notebooks/` | 笔记本列表与笔记列表页。 |
| `lib/ui/notes/note_editor_screen.dart` | 笔记编辑页：实时预览 / 源码 / 阅读三视图、保存、删除、未保存拦截。 |
| `lib/ui/notes/live_preview_editor.dart` | 实时预览编辑器：渲染态点按段落就地展开该段源码（块级 Live Preview）。 |
| `lib/ui/notes/markdown_blocks.dart` | Markdown 源码分块（`MarkdownSourceMap`，可逆拼回原文）与块的偏移量/任务序号。 |
| `lib/ui/notes/markdown_tasks.dart` | 任务列表 `- [ ]` 的定位与勾选改写纯函数（跳过围栏代码块）。 |
| `lib/ui/notes/markdown_view.dart` | Markdown 渲染组件：双链、图片占位、任务复选框回调。 |
| `lib/ui/notes/markdown_toolbar.dart` / `markdown_actions.dart` | Markdown 快捷工具条及其纯文本编辑操作（源码/段落共用）。 |
| `lib/ui/search/search_screen.dart` | 全文/向量搜索页。 |
| `lib/ui/settings/settings_screen.dart` | 后端地址、密码、连接测试、退出配置。 |
| `lib/ui/common/` | 通用组件（加载/错误/空状态、确认对话框）。 |
| `lib/ui/theme/` | Material 3 主题（浅色/深色、动态取色）。 |
| `test/` | JVM/Dart 单元测试（模型解析、URL 归一化、鉴权头、错误映射）。 |

**共享文件**（见 5.1）之外的模块文案集中在 `lib/ui/common/` 与各页自身；界面文案统一走
`lib/ui/common/strings.dart`，禁止在各页面里散落硬编码文案。

---

## 4. 构建、测试与验证

环境要求：Flutter 3.4x（Dart 3.11+）、Android SDK 36、JDK 21、`ANDROID_HOME` 已配置。
本机 Flutter 位于 `/home/rt/Android/flutter`。常用命令：

```bash
# 拉取依赖
flutter pub get

# 静态分析（门禁，不允许 error）
flutter analyze

# 单元测试
flutter test

# 打包 Debug APK（产物 build/app/outputs/flutter-apk/app-debug.apk）
flutter build apk --debug
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

### 4.1 手工/模拟器端到端验证

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
   点按某一段落，仅该段展开为源码输入框（其余仍渲染），工具条可插入 Markdown；
   点「完成」或空白处收起并还原渲染；点任务复选框应立即勾选并标为「未保存」；
   保存后用 `curl` 核对后端正文只改动了目标区域、块间空行未被打乱。

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
- 密码**只能**存放在 `flutter_secure_storage`（Android Keystore 加密），
  不得写入 `shared_preferences`、日志、异常消息、UI 明文展示（输入框用 `obscureText`）。
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
- 不引入重量级本地数据库/同步框架；本 App 无本地笔记存储，后端是唯一数据源。
- `android/app/src/debug/` 下的测试辅助代码不得影响 release 构建。

---

## 8. 已知边界（非 bug）

- **不做图片处理**：Markdown 中的 `![](path)` 不加载、不上传，按文本显示。
- **不做离线编辑**：断网时列表与笔记读取失败会提示错误，不提供本地缓存兜底。
- **不做冲突合并**：同一笔记被多处同时修改时，后保存的覆盖先保存的。
- **不做 AI 能力**：后端虽有 `/api/search/ask` 等 LLM 端点，
  但本 App 只用到搜索/笔记 CRUD，不接入模型配置与对话。
