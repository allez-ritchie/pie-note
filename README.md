# PieNote

PieNote 是一个 **Android 端的 Markdown 笔记客户端**，界面与交互参考 Obsidian，
数据完全来自你**离线部署的 [Open Notebook](https://github.com/lfnovo/open-notebook)** 后端。

- 首次启动填写后端 Base URL（如 `http://192.168.31.24:5055`）与访问密码，通过校验后即可使用；
- 笔记本 = 文件夹，笔记 = Markdown 文件，支持浏览、新建、编辑、删除、搜索；
- 编辑器提供 **实时预览 / 源码 / 阅读** 三种视图，默认「实时预览」：正文以渲染态呈现，
  点按任意段落就地展开该段 Markdown 源码编辑（参考 Obsidian Live Preview）；
- 任务列表 `- [ ]` 在实时预览与阅读视图中可直接点击勾选，立即改写正文；
- Markdown 快捷工具条、`[[双链]]` 跳转与未保存拦截；
- 图片链接暂不处理（预览中以占位符展示，不发起图片请求）。

## 功能

| 模块 | 说明 |
| --- | --- |
| 首次配置 | 后端地址 + 密码，连接测试通过才能进入；密码保存在 Android Keystore |
| 笔记本 | 列表 / 新建 / 重命名 / 归档 / 删除（级联删除笔记） |
| 笔记 | 按笔记本浏览、「全部笔记」聚合、客户端筛选、按更新时间/创建时间/标题排序 |
| 编辑器 | 实时预览 / 源码 / 阅读三视图、Markdown 工具条、字数统计、保存状态、未保存离开确认、删除 |
| 实时预览 | 渲染态直接编辑：点按段落就地展开该段源码，支持工具条、切到源码、点空白收起 |
| 阅读预览 | 标题/代码块/表格/引用/列表渲染；`[[双链]]` 点击跳转；外链交给系统浏览器；任务复选框可勾选 |
| 搜索 | 调用后端 `/api/search`，支持文本 / 语义检索、按笔记本限定范围、防抖搜索 |
| 设置 | 后端连接信息与连通性测试、修改后端、主题（跟随系统/浅色/深色）、清除配置 |

## 技术栈

- Flutter（Dart 3.11+）/ Material 3
- `flutter_riverpod` 2.6 状态管理（`AsyncNotifier` / `AsyncValue` 三态）
- `http` 网络请求，统一 Bearer 鉴权与错误映射
- `flutter_secure_storage`（Android Keystore）保存密码，`shared_preferences` 保存地址与主题
- `flutter_markdown_plus` 渲染 Markdown，`url_launcher` 打开外链

## 后端 API 约定

后端接口以运行实例的 `/openapi.json` 与 `/docs` 为准。客户端用到的关键点：

- 鉴权：所有业务接口带请求头 `Authorization: Bearer <OPEN_NOTEBOOK_PASSWORD>`；
  `/api/auth/status` 无需鉴权，用于探测是否启用密码。
- 笔记本：`GET/POST /api/notebooks`、`GET/PUT/DELETE /api/notebooks/{id}`。
- 笔记：`GET /api/notes?notebook_id=...`、`GET/POST/PUT/DELETE /api/notes/{id}`。
- 搜索：`POST /api/search`，返回 `{results, total_count, search_type}`，`results` 元素为宽松解析的 object。

完整约定与坑点（id 前缀、UTC 时间格式、可空字段等）见 [AGENTS.md](AGENTS.md)。

## 构建与运行

环境：Flutter 3.4x、Android SDK 36、JDK 21。

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

## 目录结构

```
lib/
├── app.dart                 # 根组件：主题 + 配置门禁
├── main.dart                # 入口
├── data/                    # 模型、HTTP 客户端、配置存储、业务仓库
├── state/providers.dart     # Riverpod providers
└── ui/
    ├── setup/               # 首次配置页
    ├── home/                # 底部导航骨架
    ├── notebooks/           # 笔记本列表、笔记列表
    ├── notes/               # 编辑器三视图、实时预览、Markdown 预览/分块/任务勾选
    ├── search/              # 搜索
    ├── settings/            # 设置
    ├── common/              # 通用文案/组件/跳转/格式化
    └── theme/               # Material 3 主题
```

## 已知边界

- 实时预览是「块级」而非「行内」揭示：点按后展开的是整段（空行分隔的块或标题），
  不做 Obsidian 那种光标级、只揭示当前行标记的效果；
- 不渲染 Markdown 图片（`![]()` 显示占位符，不加载、不上传）；
- 不做离线缓存与冲突合并：后端是唯一数据源，后保存者覆盖先保存者；
- 不接入后端的 AI/对话能力，只使用笔记 CRUD 与搜索接口。

## 协作

多 AI 会话协作、写入边界、提交规范见 [AGENTS.md](AGENTS.md)。
