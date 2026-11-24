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

  // ---------------------------------------------------------------------------
  // 单条笔记的「更多」菜单
  // ---------------------------------------------------------------------------

  static const String moreTooltip = '更多';
  static const String moveToNotebook = '移至笔记本';
  static const String duplicate = '创建副本';
  static const String pin = '置顶';
  static const String unpin = '取消置顶';
  static const String pinnedBadge = '置顶';
  static const String pinnedSection = '置顶';
  static const String othersSection = '其它笔记';

  /// 置顶只存在本设备，必须提示，避免用户以为跨设备同步。
  static const String pinLocalOnlyHint = '置顶仅记录在本设备，不会同步到后端或其它设备。';

  static const String renameTitle = '重命名笔记';
  static const String renameHint = '输入新的笔记标题';
  static const String renamedToast = '标题已更新';
  static const String renameFailed = '重命名失败';
  static const String pinToast = '已置顶';
  static const String unpinToast = '已取消置顶';
  static const String duplicateToast = '已创建副本';
  static const String duplicateFailed = '创建副本失败';
  static const String moveToast = '笔记已移动';
  static const String moveFailed = '移动失败';
  static const String moveToAllNotes = '全部笔记（不属于任何笔记本）';

  static String movedToToast(String notebook) => '已移动到「$notebook」';

  // 「移至笔记本」对话框
  static const String moveDialogTitle = '移至笔记本';
  static const String moveDialogMessage = '选择目标笔记本：移动后这篇笔记会从当前列表消失。';
  static const String moveEmptyTitle = '还没有笔记本';
  static const String moveEmptyMessage = '请先在「笔记本」页新建一个笔记本。';
  static const String moveConfirm = '移动';
  static const String moveSameNotebookHint = '已在该笔记本中';

  /// 移动是「复制 + 删除」，笔记 id 会变；提前告知会打开新标签页。
  static const String moveNote = '移动会生成新的笔记 id，已打开的这篇笔记标签页会自动切到新笔记。';

  // ---------------------------------------------------------------------------
  // 批量选择
  // ---------------------------------------------------------------------------

  static const String select = '选择';
  static const String selectAll = '全选';
  static const String selectNone = '取消全选';
  static const String invertSelection = '反选';
  static const String exitSelection = '退出多选';
  static const String selectedCountHint = '点击一行进入多选，长按菜单可单独操作';
  static const String selectTooltip = '多选笔记';
  static const String dragSelectHint = '按住 Shift 点击可连续选择';

  static String selectedCount(int count) => '已选 $count 项';

  static const String batchDeleteTitle = '删除所选笔记';
  static const String batchMoveTitle = '移动所选笔记';
  static const String batchPinTitle = '置顶所选笔记';
  static const String batchUnpinTitle = '取消置顶所选笔记';
  static const String batchDuplicate = '创建副本';
  static const String batchMore = '更多批量操作';
  static const String batchSelectAllInFilter = '全选筛选结果';

  static String batchDeleteMessage(int count) =>
      '确定删除所选的 $count 条笔记吗？删除后不可恢复。';
  static String batchMoveMessage(int count, String notebook) =>
      '把所选的 $count 条笔记移到「$notebook」？';
  static String batchPinnedToast(int count) => '已置顶 $count 条笔记';
  static String batchUnpinnedToast(int count) => '已取消置顶 $count 条笔记';
  static String batchDeletedToast(int count) => '已删除 $count 条笔记';
  static String batchDuplicatedToast(int count) => '已创建 $count 条副本';
  static String batchMovedToast(int count, String notebook) =>
      '已移动 $count 条笔记到「$notebook」';

  /// 批量操作是逐条请求，部分失败时必须汇总，不能只报成功。
  static String batchPartialFailure(int failed, int total) =>
      '有 $failed / $total 条笔记操作失败，请刷新后重试';
  static String batchAllFailed(int total) => '$total 条笔记全部操作失败';
}
