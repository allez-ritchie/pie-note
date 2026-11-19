/// 笔记列表页文案。
class NotesStrings {
  const NotesStrings._();

  static const String create = '新建笔记';
  static const String filterHint = '在列表中筛选标题或正文';
  static const String emptyTitle = '还没有笔记';
  static const String emptyMessage = '点击右下角按钮，写下第一条 Markdown 笔记。';
  static const String emptyAllTitle = '还没有任何笔记';
  static const String emptyAllMessage = '在任意笔记本中新建笔记后，会汇总显示在这里。';
  static const String filterEmptyTitle = '没有匹配的笔记';
  static const String filterEmptyMessage = '换个关键词试试，或清空筛选条件。';
  static const String loadErrorTitle = '笔记加载失败';
  static const String deleteTitle = '删除笔记';
  static const String delete = '删除';
  static const String aiBadge = 'AI';
  static const String updatedAt = '更新于';
  static const String sortTooltip = '排序';
  static const String sortUpdated = '最近更新';
  static const String sortCreated = '最近创建';
  static const String sortTitle = '按标题';
  static const String deletedToast = '笔记已删除';
  static const String noTitle = '无标题笔记';

  static String deleteMessage(String name) => '确定删除「$name」吗？删除后不可恢复。';
}
