import 'package:flutter/material.dart';

import '../notebooks/notes_screen.dart';
import '../notes/note_editor_screen.dart';
import '../setup/setup_screen.dart';

/// 页面跳转的统一入口。
///
/// 各页面通过这里跳转，避免互相直接依赖具体构造函数签名；
/// 编辑器统一返回 `true` 表示「内容有变更」，调用方据此刷新列表。
class AppNavigator {
  const AppNavigator._();

  /// 打开某个笔记本（或 `notebookId == null` 的全部笔记）的笔记列表。
  static Future<void> openNotes(
    BuildContext context, {
    required String title,
    String? notebookId,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotesScreen(title: title, notebookId: notebookId),
      ),
    );
  }

  /// 打开笔记编辑器；[noteId] 为空表示新建。
  static Future<bool?> openEditor(
    BuildContext context, {
    String? noteId,
    String? notebookId,
    String? initialTitle,
    String? initialContent,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => NoteEditorScreen(
          noteId: noteId,
          notebookId: notebookId,
          initialTitle: initialTitle,
          initialContent: initialContent,
        ),
      ),
    );
  }

  /// 打开后端配置页（首次配置或修改配置）。
  static Future<void> openSetup(
    BuildContext context, {
    String? initialBaseUrl,
    String? initialPassword,
    bool isEditing = false,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SetupScreen(
          initialBaseUrl: initialBaseUrl,
          initialPassword: initialPassword,
          isEditing: isEditing,
        ),
      ),
    );
  }
}
