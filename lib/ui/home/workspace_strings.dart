import '../common/app_platform.dart';

/// 多标签工作区文案。
///
/// 桌面标签条、移动端悬浮工具栏与标签总览共用；通用词汇（返回 / 关闭等）
/// 复用 `lib/ui/common/strings.dart` 的 `S`，快捷键修饰键随平台显示 Ctrl / ⌘。
class WorkspaceStrings {
  const WorkspaceStrings._();

  // 标签页
  static const String newNoteTab = '新建笔记';
  static const String untitledNote = '无标题笔记';
  static const String newTab = '新建笔记';
  static String get newTabTooltip =>
      '新建笔记标签页（${AppPlatform.shortcutKeyLabel}+T）';
  static String get closeTab => '关闭标签页（${AppPlatform.shortcutKeyLabel}+W）';
  static const String closeCurrent = '关闭当前标签页';
  static const String closeOthers = '关闭其他标签页';
  static const String closeToRight = '关闭右侧标签页';
  static const String closeAll = '关闭全部标签页';
  static const String more = '更多';
  static const String tabs = '标签页';
  static const String tabListTooltip = '多标签页';

  // 空工作区
  static const String emptyTitle = '没有打开的标签页';
  static const String emptyMessage = '从左侧选择「笔记本」或「搜索」，也可以直接新建一条笔记。';
  static const String openNotebooks = '打开笔记本';
  static const String openSearch = '打开搜索';

  // 关闭未保存的标签页
  static const String closeDirtyTitle = '有未保存的修改';
  static const String saveAndClose = '保存并关闭';
  static const String closeWithoutSaving = '不保存';
  static const String closeDirtyCancel = '取消';

  static String closeDirtyMessage(String title) => '「$title」还有未保存的修改，关闭前要保存吗？';

  static String closeTabsMessage(int count) => '将关闭 $count 个标签页，未保存的修改会丢失。';

  // 标签总览（移动端）
  static const String overviewTitle = '多标签';
  static const String overviewDone = '完成';
  static const String overviewNewNote = '新建笔记';
  static const String overviewClose = '关闭';
  static const String overviewEmpty = '还没有打开的标签页';
  static const String overviewDirty = '未保存';

  static String tabCount(int count) => '$count 个标签页';

  // 快捷键提示（桌面端）
  static String get shortcutTabs =>
      '标签页：${AppPlatform.shortcutKeyLabel}+1..9 切换';
  static String get shortcutNextTab => '下一个标签页：Ctrl+Tab';
  static String get shortcutCloseTab =>
      '关闭当前标签页：${AppPlatform.shortcutKeyLabel}+W';
}
