/// 笔记本列表页文案。
class NotebooksStrings {
  const NotebooksStrings._();

  static const String title = '笔记本';
  static const String allNotes = '全部笔记';
  static const String allNotesSubtitle = '跨笔记本浏览最近更新的笔记';
  static const String create = '新建笔记本';
  static const String createDialogTitle = '新建笔记本';
  static const String createDialogHint = '例如：工作记录';
  static const String renameDialogTitle = '重命名笔记本';
  static const String renameDialogHint = '输入新的笔记本名称';
  static const String emptyTitle = '还没有笔记本';
  static const String emptyMessage = '在 Open Notebook 中新建一个笔记本，把相关笔记放在一起。';
  static const String deleteTitle = '删除笔记本';
  static const String archive = '归档';
  static const String unarchive = '取消归档';
  static const String showArchived = '显示已归档';
  static const String hideArchived = '隐藏已归档';
  static const String archivedBadge = '已归档';
  static const String editName = '重命名';
  static const String delete = '删除';
  static const String updatedAt = '更新于';
  static const String createdToast = '笔记本已创建';
  static const String updatedToast = '笔记本已更新';
  static const String deletedToast = '笔记本已删除';
  static const String loadErrorTitle = '笔记本加载失败';
  static const String sortHint = '按更新时间排序';

  static String deleteMessage(String name) =>
      '将删除「$name」及其中的全部笔记，操作不可恢复。';

  static String notebookCount(int count) => '$count 个笔记本';

  /// 单个笔记本内的笔记数量，例如 `2 条笔记`。
  static String noteCount(int count) => '$count 条笔记';
}
