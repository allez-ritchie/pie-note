import '../common/app_platform.dart';

/// 笔记编辑页文案。
class EditorStrings {
  const EditorStrings._();

  static const String newNote = '新建笔记';
  static const String editTitle = '编辑笔记';
  static const String titleHint = '标题';
  static const String contentHint = '开始书写 Markdown…';
  static const String save = '保存';

  /// 保存按钮的提示文案（快捷键随平台显示 Ctrl 或 ⌘）。
  static String get saveShortcut => '保存（${AppPlatform.shortcutKeyLabel}+S）';
  static const String saving = '保存中…';
  static const String savedToast = '笔记已保存';
  static const String saveFailed = '保存失败';
  static const String deleteTitle = '删除笔记';
  static const String deleteMessage = '确定删除当前笔记吗？删除后不可恢复。';
  static const String delete = '删除';
  static const String deletedToast = '笔记已删除';
  static const String unsavedTitle = '有未保存的修改';
  static const String unsavedMessage = '离开前是否保存当前修改？';
  static const String unsavedSaveAndLeave = '保存并离开';
  static const String unsavedDiscard = '不保存';
  static const String loadErrorTitle = '笔记加载失败';
  static const String untitled = '无标题笔记';
  static const String savedAt = '上次保存';
  static const String unsavedBadge = '未保存';

  /// 字数统计。
  static String charCount(int count) => '$count 字';
  static const String neverSaved = '尚未保存';
  static const String emptyPreview = '（内容为空，切回编辑模式开始书写）';

  // 视图模式（参考 Obsidian：实时预览 / 源码 / 阅读）
  static const String modeLive = '实时预览';
  static const String modeSource = '源码';
  static const String modeReading = '阅读';
  static const String switchMode = '视图模式';
  static const String startWriting = '开始书写';
  static const String paneSource = 'MARKDOWN 源码';
  static const String taskDone = '已完成';
  static const String taskTodo = '未完成';

  // 大纲
  static const String outline = '大纲';
  static const String outlineTooltip = '大纲：按标题跳转';
  static const String outlineHide = '隐藏大纲';
  static const String outlineEmptyTitle = '这篇笔记还没有标题';
  static const String outlineEmptyMessage = '用「# 标题」写下小标题后，这里会生成可跳转的大纲。';
  static const String outlineUntitledHeading = '（空标题）';
  static const String outlineCollapseAll = '全部折叠';
  static const String outlineExpandAll = '全部展开';
  static const String outlineCollapseOne = '折叠此标题';
  static const String outlineExpandOne = '展开此标题';

  /// 大纲侧栏左侧分隔条的提示：可左右拖动调宽，双击恢复默认。
  static const String outlineResizeTooltip = '拖动调整大纲宽度，双击恢复默认';

  static String outlineCount(int count) => '$count 个标题';

  /// 目录里的锚点找不到对应标题（可能标题被改名 / 删掉了）。
  static String anchorNotFound(String fragment) => '没找到锚点「$fragment」对应的标题';

  // Markdown 工具条
  static const String toolH1 = '一级标题';
  static const String toolH2 = '二级标题';
  static const String toolBold = '加粗';
  static const String toolItalic = '斜体';
  static const String toolStrike = '删除线';
  static const String toolCode = '行内代码';
  static const String toolCodeBlock = '代码块';
  static const String toolBullet = '无序列表';
  static const String toolNumbered = '有序列表';
  static const String toolQuote = '引用';
  static const String toolCheckbox = '待办事项';
  static const String toolLink = '链接';
  static const String toolWiki = '双链笔记';
}
