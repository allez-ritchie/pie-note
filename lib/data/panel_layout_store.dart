import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

/// 可拖拽分栏的宽度偏好（本设备）。
///
/// 为什么放本地：栏宽是**本设备的浏览偏好**，不是笔记内容，后端也没有对应字段
/// （见 AGENTS.md 2.5 节对置顶的同类处理）。窗口尺寸因设备而异，把某台电脑的
/// 列宽同步到手机上只会挤坏布局，因此只存 `shared_preferences`。
///
/// 存的是「用户最后一次拖出来的宽度」，不存比例：窗口缩放时宽度保持稳定，
/// 用户想恢复默认就双击分隔条（[save] 传 null 即清除）。
class PanelLayoutStore {
  PanelLayoutStore({SharedPreferences? preferences})
    : _preferences = preferences;

  /// 笔记本双栏里左栏（笔记本列表）的宽度。
  static const String notebookPaneWidthKey = 'layout.notebooks_pane_width';

  /// 笔记编辑页大纲侧栏的宽度。
  static const String outlinePaneWidthKey = 'layout.outline_pane_width';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<double?> loadNotebookPaneWidth() async =>
      _readWidth(notebookPaneWidthKey);

  Future<void> saveNotebookPaneWidth(double? width) =>
      _writeWidth(notebookPaneWidthKey, width);

  Future<double?> loadOutlinePaneWidth() async =>
      _readWidth(outlinePaneWidthKey);

  Future<void> saveOutlinePaneWidth(double? width) =>
      _writeWidth(outlinePaneWidthKey, width);

  /// 读取宽度：缺失、非数字、非有限值或非正数都按「没有偏好」处理，
  /// 让界面回落到默认宽度而不是渲染出 0 宽或 NaN 的分栏。
  Future<double?> _readWidth(String key) async {
    try {
      final prefs = await _prefs;
      final value = prefs.get(key);
      final double? width = switch (value) {
        double v => v,
        int v => v.toDouble(),
        String v => double.tryParse(v),
        _ => null,
      };
      if (width == null || !width.isFinite || width <= 0) return null;
      return width;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeWidth(String key, double? width) async {
    // 写偏好失败（无平台实现 / 存储只读）不该让界面报错：调用方是 unawaited，
    // 抛出去会变成未捕获异常；列宽丢失只是回到默认值。
    try {
      final prefs = await _prefs;
      if (width == null || !width.isFinite || width <= 0) {
        await prefs.remove(key);
        return;
      }
      await prefs.setDouble(key, width);
    } catch (_) {
      // 忽略：属于「记不住」而不是「用不了」。
    }
  }

  /// 把任意来源的宽度夹进 [min] ~ [max]；非法值回落到 [fallback]。
  static double clampWidth(
    double? width, {
    required double fallback,
    required double min,
    required double max,
  }) {
    final upper = math.max(min, max);
    if (width == null || !width.isFinite) return fallback.clamp(min, upper);
    return width.clamp(min, upper);
  }
}
