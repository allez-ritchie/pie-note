import '../common/strings.dart';

/// 时间与数量的展示格式化。
class Formatters {
  const Formatters._();

  /// 列表里的「相对时间」：刚刚 / n 分钟前 / n 小时前 / 昨天 / MM-dd / yyyy-MM-dd。
  static String relativeTime(DateTime? time, {DateTime? now}) {
    if (time == null) return '';
    final current = (now ?? DateTime.now()).toLocal();
    final local = time.toLocal();
    final diff = current.difference(local);
    if (diff.isNegative || diff.inSeconds < 60) return S.justNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes} ${S.minutesAgo}';
    if (diff.inHours < 24) return '${diff.inHours} ${S.hoursAgo}';
    final today = DateTime(current.year, current.month, current.day);
    final day = DateTime(local.year, local.month, local.day);
    if (today.difference(day).inDays == 1) return S.yesterday;
    if (local.year == current.year) {
      return '${_two(local.month)}-${_two(local.day)}';
    }
    return '${local.year}-${_two(local.month)}-${_two(local.day)}';
  }

  /// 完整时间：`yyyy-MM-dd HH:mm`。
  static String dateTime(DateTime? time) {
    if (time == null) return '';
    final local = time.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)} '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  /// 笔记数量，例如 `3 条笔记`。
  static String noteCount(int count) => '$count ${S.noteUnit}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}
