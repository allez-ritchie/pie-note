/// 笔记编辑页文案。
class EditorStrings {
  const EditorStrings._();

  static const String newNote = '新建笔记';
  static const String titleHint = '标题';
  static const String contentHint = '开始书写 Markdown…';
  static const String save = '保存';
  static const String saving = '保存中…';
  static const String savedToast = '笔记已保存';
  static const String saveFailed = '保存失败';
  static const String preview = '预览';
  static const String edit = '编辑';
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
  static const String neverSaved = '尚未保存';
  static const String emptyPreview = '（内容为空，切回编辑模式开始书写）';

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
