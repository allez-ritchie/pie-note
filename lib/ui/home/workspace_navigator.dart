import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_models.dart';
import '../../state/workspace.dart';
import '../common/strings.dart';
import '../home/workspace_strings.dart';
import '../notes/editor_strings.dart';

/// 工作区标签页的统一打开入口。
///
/// 页面（笔记本列表、笔记列表、来源列表、对话、搜索、Markdown 双链）不直接
/// 构造编辑器路由，而是把目标交给工作区：同一条笔记已经打开时激活原标签页，
/// 否则新开一个；同一个笔记本的来源 / 对话 / 笔记列表也只保留一个标签页。
class WorkspaceNavigator {
  const WorkspaceNavigator._();

  static WorkspaceNotifier _notifier(WidgetRef ref) =>
      ref.read(workspaceProvider.notifier);

  /// 激活或打开一级页面（笔记本 / 来源 / 搜索 / 设置）。
  static String openSection(WidgetRef ref, WorkspaceTabKind kind) {
    return _notifier(ref).openSection(kind, title: _sectionTitle(kind));
  }

  /// 打开某个笔记本的笔记列表；[notebookId] 为 null 表示「全部笔记」。
  static String openNotes(
    WidgetRef ref, {
    required String title,
    String? notebookId,
  }) {
    return _notifier(ref).openNotes(notebookId: notebookId, title: title);
  }

  /// 打开某个笔记本的来源列表；[notebookId] 为 null 表示「全部来源」。
  static String openSources(
    WidgetRef ref, {
    required String title,
    String? notebookId,
  }) {
    return _notifier(ref).openSources(notebookId: notebookId, title: title);
  }

  /// 打开某个笔记本的来源列表（标题自动带上笔记本名）。
  static String openSourcesOf(WidgetRef ref, Notebook notebook) {
    return openSources(
      ref,
      title: WorkspaceStrings.sourcesTabOf(notebook.name),
      notebookId: notebook.id,
    );
  }

  /// 与某个笔记本对话。
  static String openChat(WidgetRef ref, Notebook notebook) {
    return _notifier(ref).openChat(
      notebookId: notebook.id,
      title: WorkspaceStrings.chatTabOf(notebook.name),
    );
  }

  /// 打开一条已有笔记；[title] 用于标签条展示，可后续由编辑页校正。
  static String openNote(
    WidgetRef ref, {
    required String noteId,
    required String title,
    String? notebookId,
  }) {
    return _notifier(ref).openNote(
      noteId: noteId,
      title: title.isEmpty ? WorkspaceStrings.untitledNote : title,
      notebookId: notebookId,
    );
  }

  /// 新建一条草稿笔记标签页。
  static String openDraft(WidgetRef ref, {String? notebookId}) {
    return _notifier(
      ref,
    ).openDraft(notebookId: notebookId, title: WorkspaceStrings.newNoteTab);
  }

  static String _sectionTitle(WorkspaceTabKind kind) {
    return switch (kind) {
      WorkspaceTabKind.notebooks => S.tabNotebooks,
      WorkspaceTabKind.sources => S.tabSources,
      WorkspaceTabKind.search => S.tabSearch,
      WorkspaceTabKind.settings => S.tabSettings,
      WorkspaceTabKind.notes => EditorStrings.editTitle,
      WorkspaceTabKind.note => WorkspaceStrings.untitledNote,
      WorkspaceTabKind.chat => S.tabChat,
    };
  }
}
