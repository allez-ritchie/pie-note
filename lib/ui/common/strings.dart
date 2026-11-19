/// 全应用通用文案与常量。
///
/// 约定：所有用户可见文案集中管理，页面里禁止硬编码。
/// 各功能模块可在自己目录下维护 `<feature>_strings.dart`。
class S {
  const S._();

  static const String appName = 'PieNote';
  static const String appSlogan = '连接你的 Open Notebook，随手记录 Markdown 笔记';
  static const String appVersion = '0.1.0';

  // 通用按钮 / 动作
  static const String ok = '确定';
  static const String cancel = '取消';
  static const String save = '保存';
  static const String delete = '删除';
  static const String rename = '重命名';
  static const String edit = '编辑';
  static const String retry = '重试';
  static const String refresh = '刷新';
  static const String close = '关闭';
  static const String back = '返回';
  static const String create = '新建';
  static const String loading = '加载中…';

  // 通用错误
  static const String networkErrorTitle = '无法连接后端';
  static const String unknownError = '发生未知错误，请稍后重试';
  static const String notConfiguredTitle = '尚未配置后端';
  static const String notConfiguredMessage = '请先在设置页填写 Open Notebook 的后端地址与访问密码。';
  static const String goToSetup = '去配置';

  // 时间 / 数量
  static const String justNow = '刚刚';
  static const String minutesAgo = '分钟前';
  static const String hoursAgo = '小时前';
  static const String yesterday = '昨天';
  static const String noteUnit = '条笔记';

  // 导航
  static const String tabNotebooks = '笔记本';
  static const String tabSearch = '搜索';
  static const String tabSettings = '设置';
}
