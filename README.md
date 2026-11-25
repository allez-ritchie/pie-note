# PieNote

PieNote 是一个 **Markdown 笔记客户端**（Android + Linux/Windows 桌面），界面与交互参考 Obsidian，
数据完全来自你**离线部署的 [Open Notebook](https://github.com/lfnovo/open-notebook)** 后端。

- 首次启动填写后端 Base URL（如 `http://192.168.31.24:5055`）与访问密码，通过校验后即可使用；
- 笔记本 = 文件夹，笔记 = Markdown 文件，支持浏览、新建、编辑、删除、搜索；
- 编辑器提供 **实时预览 / 源码 / 阅读** 三种视图，默认「实时预览」：正文以渲染态呈现，
  点按任意段落，该段就地变成不带边框的 Markdown 源码编辑（参考 Obsidian Live Preview），
  点按别处即自动收起、恢复渲染；光标在段首按 `Backspace` 会删掉段前空行、把上一段接过来
  （光标落在上一行行尾并展开该段源码），与普通文本编辑器一致；
- 标题上方留白参考 Obsidian（越大的标题越松），正文分节更清晰；
- 保存成功的提示是**顶部半透明小横幅**（不拦截点击、自动消失），不会遮住底部编辑区；
- 任务列表 `- [ ]` 在实时预览与阅读视图中可直接点击勾选，立即改写正文；
- Markdown 快捷工具条、`[[双链]]` 跳转与未保存拦截；
- **大纲视图**：按标题（`#` ~ `######`）自动生成大纲，宽窗口是右侧侧栏、窄窗口是底部面板；
  点任意标题即可在实时预览 / 源码 / 阅读三视图里跳转，并高亮当前所在标题；
  有子标题的条目带「›」折叠箭头（展开时朝下），标题栏可「全部折叠 / 全部展开」；
- **多标签页工作区**：笔记本、搜索、设置与每篇笔记都是标签页，可并行打开多篇笔记；
  桌面端是侧边导航 + 顶部标签条（`×` / 中键关闭、右键批量关闭、`Ctrl/Cmd + W` 关闭、
  `+T` 新建、`+Tab` 循环、`+1..9` 跳转），手机端是底部悬浮胶囊工具栏 + 多标签总览
  （上划自动隐藏、下划显示、点按停下不回显）；
- **横竖屏 / 桌面窗口自适应**：手机竖屏单栏 + 悬浮工具栏，横屏与桌面窗口自动切侧边导航，
  宽窗口下笔记本与笔记并排、阅读视图左右分栏，编辑器支持 `Ctrl/Cmd + S` 保存；
- **来源（Sources）**：为笔记本添加网页链接 / 本地文件 / 纯文本来源，
  后端异步抽取正文、生成洞见与向量索引，客户端轮询处理状态并可查看正文与洞见；
- **与笔记本对话**：基于来源与笔记构建上下文，把问题交给后端 LLM 回答；
  支持多会话、上下文逐项勾选（不进 / 仅洞见 / 全文）、按会话选择模型、AI 回答一键存为笔记；
- 图片链接暂不处理（预览中以占位符展示，不发起图片请求）。

## 功能

| 模块 | 说明 |
| --- | --- |
| 首次配置 | 后端地址 + 密码，连接测试通过才能进入；密码保存在 Android Keystore |
| 笔记本 | 列表 / 新建 / 重命名 / 归档 / 删除（级联删除笔记） |
| 笔记 | 按笔记本浏览、「全部笔记」聚合、客户端筛选、按更新时间/创建时间/标题排序 |
| 编辑器 | 实时预览 / 源码 / 阅读三视图、Markdown 工具条（多行选区逐行加/去行前缀）、字数统计、保存状态、未保存离开确认、删除 |
| 实时预览 | 渲染态直接编辑：点按段落，该段就地变成无边框源码输入框（只剩源码本身），支持工具条；点按别处自动收起；桌面端按住左键向上/向下拖出输入框可跨多个段落连续选中 Markdown 源码 |
| 阅读预览 | 标题/代码块/表格/引用/列表渲染；`[[双链]]` 点击跳转；外链交给系统浏览器；任务复选框可勾选；正文可跨段落、跨小节连续选择并一次复制 |
| 大纲 | 按 ATX 标题生成层级大纲（跳过代码块）；点标题在三种视图里跳转，编辑时跟随光标、阅读时跟随滚动高亮当前标题；有子标题的条目可单独折叠（箭头随状态旋转），标题栏可一键「全部折叠 / 全部展开」；宽 ≥ 1080 为右侧侧栏，否则为底部面板 |
| 搜索 | 调用后端 `/api/search`，支持文本 / 语义检索、按笔记本限定范围、防抖搜索 |
| 来源 | 列表 + 处理状态胶囊（自动轮询）、添加链接/文本/文件来源、正文与洞见详情、重命名/删除/失败重试、可选向量化 |
| 对话 | 会话新建/切换/重命名/删除、上下文勾选与 token 预估、模型覆盖、Markdown 回答、复制 / 保存为笔记、失败可重试 |
| 设置 | 后端连接信息与连通性测试、修改后端、主题（跟随系统/浅色/深色）、清除配置 |
| 多标签 | 标签页状态集中在 `lib/state/workspace.dart`；同一篇笔记只会有一个标签页；关闭前统一确认未保存修改；标签页内容 `IndexedStack` 保活（草稿、滚动位置、搜索词都不丢） |
| 响应式 | 断点驱动：侧边导航 + 顶部标签条（宽 ≥ 720）、列表双栏（宽 ≥ 840 且高 ≥ 480）、编辑器分栏（宽 ≥ 900 且高 ≥ 420）；窄屏为悬浮胶囊工具栏 + 标签总览 |
| 桌面端 | Linux / Windows 原生窗口（默认 1180×820、最小 420×560），同一套 Flutter 代码 |

## 技术栈

- Flutter（Dart 3.11+）/ Material 3
- `flutter_riverpod` 2.6 状态管理（`AsyncNotifier` / `AsyncValue` 三态）
- `http` 网络请求，统一 Bearer 鉴权与错误映射
- `flutter_secure_storage`（Android Keystore / Linux 系统密钥环 / Windows 凭据管理器）保存密码，`shared_preferences` 保存地址与主题
- `flutter_markdown_plus` 渲染 Markdown，`url_launcher` 打开外链，`file_selector` 选择本地文件作为来源

## 后端 API 约定

后端接口以运行实例的 `/openapi.json` 与 `/docs` 为准。客户端用到的关键点：

- 鉴权：所有业务接口带请求头 `Authorization: Bearer <OPEN_NOTEBOOK_PASSWORD>`；
  `/api/auth/status` 无需鉴权，用于探测是否启用密码。
- 笔记本：`GET/POST /api/notebooks`、`GET/PUT/DELETE /api/notebooks/{id}`。
- 笔记：`GET /api/notes?notebook_id=...`、`GET/POST/PUT/DELETE /api/notes/{id}`。
- 搜索：`POST /api/search`，返回 `{results, total_count, search_type}`，`results` 元素为宽松解析的 object。
- 来源：`GET/POST /api/sources`（创建走 **multipart/form-data**）、`GET/DELETE /api/sources/{id}`、
  `POST /api/sources/{id}/retry`、`GET /api/sources/{id}/status`（异步处理轮询）、
  `GET /api/sources/{id}/insights`；`POST /api/notebooks/{nid}/sources/{sid}` 关联到笔记本。
- 对话：`GET/POST /api/chat/sessions`、`GET/PUT/DELETE /api/chat/sessions/{id}`、
  `POST /api/chat/context`（按 `context_config` 构建上下文）、`POST /api/chat/execute`
  （同步返回完整消息列表）；`GET /api/models` / `/api/models/defaults` 提供模型选项。
  **所有 LLM 调用都在后端完成**，客户端只透传 `model_override`（`model:<id>`）。

完整约定与坑点（id 前缀、UTC 时间格式、可空字段等）见 [AGENTS.md](AGENTS.md)。

## 构建与运行

环境：Flutter 3.4x、Android SDK 36、JDK 21；
Linux 桌面端另需 clang / cmake / ninja / GTK3 / libsecret-1-dev，Windows 桌面端需 Visual Studio 2022
的「使用 C++ 的桌面开发」工作负载（MSVC + Windows SDK）。

### Android

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
# 产物：build/app/outputs/flutter-apk/app-debug.apk
```

安装到模拟器/真机：

```bash
adb install -r build/app/outputs/flutter-apk/app-debug.apk
# 若后端在本机，先把 5055 端口映射进模拟器：
adb reverse tcp:5055 tcp:5055
```

App 内填写 Base URL（模拟器可用 `http://127.0.0.1:5055`，局域网真机用 `http://<后端IP>:5055`）
和密码 `docker exec open-notebook printenv OPEN_NOTEBOOK_PASSWORD`，点击「测试连接」→「保存并进入」。

### Linux 桌面端

编译期需要 `libsecret-1` 的开发文件（运行期用系统密钥环保存密码）：

```bash
# 有 root：sudo apt install libsecret-1-dev（Fedora: libsecret-devel / Arch: libsecret）
# 无 root：自动解包到 .desktop-deps/（已忽略，不改动系统目录）
scripts/setup_linux_deps.sh --local

eval "$(scripts/setup_linux_deps.sh --print-env)"
flutter build linux --release
# 产物：build/linux/x64/release/bundle/pie_note（整个 bundle/ 目录可直接分发）
./build/linux/x64/release/bundle/pie_note
```

- `setup_linux_deps.sh` 还会生成 clang 工具链 shim：Flutter 的 native assets 编译要求
  `clang++` 同目录下有 `ld.lld` / `ld`，Ubuntu 的 clang-18 默认不带 lld，不补会直接构建失败。
- 桌面端若没有运行中的 Secret Service（如精简的窗口管理器/远程会话），保存配置会提示
  「无法写入系统密钥环（libsecret）」并保持未保存状态，**不会**把密码写到明文存储。

### Windows 桌面端

需要 Visual Studio 2022 的「使用 C++ 的桌面开发」工作负载（MSVC v143 + Windows 10/11 SDK），
`flutter doctor -v` 里 Visual Studio 一项为 ✓ 即可；密码走系统凭据管理器，无需额外开发包。

```powershell
pwsh -File scripts/build_windows.ps1              # release 构建
pwsh -File scripts/build_windows.ps1 -DebugBuild   # debug 构建
pwsh -File scripts/build_windows.ps1 -Bundle       # 额外归档 dist/pie-note-windows-x64-<mode>.zip
# 产物：build/windows/x64/runner/Release/pie_note.exe
# 分发时要连同同目录的 data/、flutter_windows.dll 与各插件 dll 一起打包
```

- 窗口标题 `PieNote`、默认 1180×820、最小 420×560，与 Linux 端保持一致；
- runner 的 C++ 源码含中文注释，`windows/runner/CMakeLists.txt` 里的 `/utf-8` 编译选项不能删，
  否则 MSVC 在中文代码页下会因 C4819 被 `/WX` 拦成编译错误。

## 目录结构

```
lib/
├── app.dart                 # 根组件：主题 + 配置门禁
├── main.dart                # 入口
├── data/                    # 模型、HTTP 客户端、配置存储、业务仓库
├── state/providers.dart     # Riverpod providers
└── ui/
    ├── setup/               # 首次配置页
    ├── home/                # 多标签工作区外壳（标签条 / 悬浮工具栏 / 标签总览 / 导航入口）
    ├── notebooks/           # 笔记本列表、笔记列表
    ├── notes/               # 编辑器三视图、实时预览、大纲、Markdown 预览/分块/任务勾选
    ├── search/              # 搜索
    ├── sources/             # 来源：列表 / 添加（链接·文本·文件）/ 详情与洞见
    ├── chat/                # 与笔记本对话：会话、上下文、模型、消息流
    ├── settings/            # 设置
    ├── common/              # 通用文案/组件/跳转/格式化
    └── theme/               # Material 3 主题
```

## 响应式与桌面端

页面不读 `MediaQuery.orientation`，一律按可用**宽高**分支（`lib/ui/common/layout.dart`）：

| 断点 | 条件 | 行为 |
| --- | --- | --- |
| 侧边导航 + 标签条 | 宽 ≥ 720 | `NavigationRail` + 顶部标签条 |
| 列表双栏 | 宽 ≥ 840 且高 ≥ 480 | 笔记本（左）+ 笔记（右），点击不跳页 |
| 编辑器分栏 | 宽 ≥ 900 且高 ≥ 420 | 阅读视图左右分栏：渲染 + Markdown 源码 |
| 大纲侧栏 | 宽 ≥ 1080 且高 ≥ 420 | 大纲常驻右侧侧栏；更窄时点大纲图标弹底部面板 |

窄屏（< 720）用页面铺满 + 底部悬浮胶囊工具栏（后退 / 前进、搜索、新建、标签总览、
更多），标签总览是 2 列卡片页。悬浮工具栏在**上划时隐藏、下划时显示**，滚动中途点按
停下不会回显（参考 Obsidian 移动端）。

### 多标签页

- 笔记、笔记本列表、搜索、设置都是标签页；打开同一篇笔记只会切到已有标签页；
- 桌面端：标签条 `×` 或鼠标中键关闭、右键菜单「关闭其他 / 关闭右侧 / 关闭全部」，
  快捷键 `Ctrl/Cmd + W`（关闭）、`+T`（新建笔记标签页）、`+Tab` / `+Shift+Tab`（循环）、
  `+1..9`（跳到第 N 个）；
- 关闭有未保存修改的标签页时统一弹「保存并关闭 / 不保存 / 取消」；
- 新建笔记首次保存后，草稿标签页自动绑定到真实笔记并同步标题。

高度断点是必须的：手机横屏通常只有 400~450 高，只按宽度判断会把列表挤成两条细缝。
宽窗口下正文用 `ContentFrame` 限宽居中；密码存储位置、快捷键等平台差异文案走
`lib/ui/common/app_platform.dart`。

## 应用图标

图标设计源文件是 `assets/branding/app_icon.svg`（暖白圆角底板 + 三片饼图）。
改图标只需替换这个 SVG，然后跑：

```bash
python3 scripts/generate_app_icons.py   # 需要 Python 3 + Pillow + 本机 Chrome/Chromium
```

脚本会重新生成 Android 各密度 mipmap、adaptive icon（含 Android 13 单色图标）、
Windows 的 `app_icon.ico`，以及桌面窗口图标与配置页 Logo 用的
`assets/branding/app_icon.png`。**不要直接手改平台目录里的 PNG**，下次生成会被覆盖。

## 已知边界

- 实时预览是「块级」而非「行内」揭示：点按后展开的是整段（空行分隔的块或标题），
  整段源码替换该段渲染、无边框也不再显示「完成」按钮，点按别处失焦即收起；
  不做 Obsidian 那种光标级、只揭示当前行标记的效果。段首退格会把上一段接进当前编辑框
  （两段合并成一段源码），因此合并后重新分块、点按别处即恢复渲染；
- 桌面端跨行拖选靠「拖出就地输入框边界」触发：越过边界后相邻段落会并入同一个编辑框，
  选区因此覆盖多段 Markdown 源码（复制即完整源码）；触摸端不触发该扩展，仍是长按选词；
- 大纲只识别 ATX 标题（`# 标题`），不含 Setext 标题（`===` / `---` 下划线）；
  跳转是「滚动到标题」而非锚点链接，阅读视图按标题分节渲染；
- 不渲染 Markdown 图片（`![]()` 显示占位符，不加载、不上传）；
- 不做离线缓存与冲突合并：后端是唯一数据源，后保存者覆盖先保存者；
- 对话不是流式的：后端 `/api/chat/execute` 同步返回完整回答，等待期间只显示「AI 正在回答…」；
- AI 能力全部由后端承担：本 App 不内置模型配置/密钥，模型选择只是把 `model:<id>`
  透传给后端；后端未注册模型或额度不足时把错误原样展示（可重试）；
- 来源的正文抽取、洞见生成、向量化都在后端异步执行，客户端只负责触发与轮询状态。

## 协作

多 AI 会话协作、写入边界、提交规范见 [AGENTS.md](AGENTS.md)。
