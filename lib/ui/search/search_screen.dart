import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart';
import '../../data/api_models.dart';
import '../../state/providers.dart';
import '../common/strings.dart';
import '../common/widgets.dart';
import '../home/workspace_navigator.dart';
import 'search_strings.dart';

/// 全文 / 语义搜索页。
///
/// - 输入框防抖 350ms 自动搜索，回车立即搜索，清空后回到引导态；
/// - 范围（全部 / 指定笔记本）与类型（文本 / 语义）变化后立即重新搜索；
/// - 结果由 [searchProvider] 的 `AsyncValue` 驱动「加载中 / 失败 / 空 / 列表」四态。
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  /// 输入停顿多久后自动搜索。
  static const Duration _debounceDuration = Duration(milliseconds: 350);

  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;

  /// 已生效的搜索词（去掉首尾空白）；为空表示引导态。
  String _query = '';

  /// 搜索类型：`text`（默认）或 `vector`。
  String _type = 'text';

  /// 选中的笔记本；`null` 表示全部。
  String? _notebookId;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// 输入变化：清空立即回到引导态，否则防抖后触发搜索。
  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    // 同步重建，让清除按钮的出现/消失跟上输入（搜索本身仍在防抖之后）。
    setState(() {
      if (trimmed.isEmpty) _query = '';
    });
    if (trimmed.isEmpty) return;
    _debounce = Timer(_debounceDuration, () {
      if (!mounted || trimmed == _query) return;
      setState(() => _query = trimmed);
    });
  }

  /// 回车立即搜索（同时收起键盘，方便查看结果）。
  void _submit() {
    _debounce?.cancel();
    FocusScope.of(context).unfocus();
    final trimmed = _controller.text.trim();
    if (trimmed == _query) return;
    setState(() => _query = trimmed);
  }

  void _clearInput() {
    _debounce?.cancel();
    _controller.clear();
    setState(() => _query = '');
  }

  /// 打开命中笔记：作为新标签页（已打开则切过去）。
  void _openHit(SearchQuery query, SearchHit hit) {
    WorkspaceNavigator.openNote(
      ref,
      noteId: hit.noteId,
      title: hit.title ?? SearchStrings.unnamedNote,
    );
    // 编辑后回到本页时刷新结果，避免展示已过期的正文。
    ref.invalidate(searchProvider(query));
  }

  @override
  Widget build(BuildContext context) {
    final notebooksAsync = ref.watch(notebooksProvider);
    final notebooks = notebooksAsync.valueOrNull ?? const <Notebook>[];

    // 选中的笔记本在列表里找不到（加载失败 / 已删除）时降级为「全部」，不阻塞搜索。
    final selectedNotebookId =
        (_notebookId != null &&
            notebooks.any((notebook) => notebook.id == _notebookId))
        ? _notebookId
        : null;
    final scopeDegraded =
        _notebookId != null &&
        selectedNotebookId == null &&
        notebooksAsync.hasError;

    final query = SearchQuery(
      query: _query,
      notebookIds: selectedNotebookId == null
          ? const <String>[]
          : <String>[selectedNotebookId],
      type: _type,
    );
    // 空查询不请求后端，直接展示引导态。
    final searchAsync = _query.isEmpty ? null : ref.watch(searchProvider(query));

    return Scaffold(
      appBar: AppBar(title: const Text(SearchStrings.title)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _controller,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: SearchStrings.searchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _controller.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: SearchStrings.clearInput,
                          onPressed: _clearInput,
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _SearchOptions(
                notebooks: notebooks,
                notebooksLoading:
                    notebooksAsync.isLoading && !notebooksAsync.hasValue,
                selectedNotebookId: selectedNotebookId,
                onNotebookChanged: (id) => setState(() => _notebookId = id),
                type: _type,
                onTypeChanged: (value) => setState(() => _type = value),
                degradedHint:
                    scopeDegraded ? SearchStrings.scopeUnavailable : null,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: searchAsync == null
                  ? const AppEmptyView(
                      icon: Icons.manage_search_rounded,
                      title: SearchStrings.guideTitle,
                      message: SearchStrings.guideMessage,
                    )
                  : _SearchResults(
                      async: searchAsync,
                      onRetry: () => ref.invalidate(searchProvider(query)),
                      onOpen: (hit) => _openHit(query, hit),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 搜索范围 + 搜索类型两个控件（窄屏自动换行）。
class _SearchOptions extends StatelessWidget {
  const _SearchOptions({
    required this.notebooks,
    required this.notebooksLoading,
    required this.selectedNotebookId,
    required this.onNotebookChanged,
    required this.type,
    required this.onTypeChanged,
    this.degradedHint,
  });

  final List<Notebook> notebooks;
  final bool notebooksLoading;
  final String? selectedNotebookId;
  final ValueChanged<String?> onNotebookChanged;
  final String type;
  final ValueChanged<String> onTypeChanged;
  final String? degradedHint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildScope(context),
            SegmentedButton<String>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const <ButtonSegment<String>>[
                ButtonSegment<String>(
                  value: 'text',
                  label: Text(SearchStrings.typeText),
                  icon: Icon(Icons.article_outlined, size: 18),
                ),
                ButtonSegment<String>(
                  value: 'vector',
                  label: Text(SearchStrings.typeVector),
                  icon: Icon(Icons.hub_outlined, size: 18),
                ),
              ],
              selected: <String>{type},
              onSelectionChanged: (selection) => onTypeChanged(selection.first),
            ),
          ],
        ),
        if (type == 'vector') ...[
          const SizedBox(height: 8),
          _hint(scheme, theme, Icons.info_outline_rounded, SearchStrings.vectorHint),
        ],
        if (degradedHint != null) ...[
          const SizedBox(height: 8),
          _hint(scheme, theme, Icons.warning_amber_rounded, degradedHint!),
        ],
      ],
    );
  }

  /// 笔记本范围下拉框：第一项固定为「全部笔记本」。
  ///
  /// 笔记本列表加载中或加载失败时只保留「全部」，搜索照常可用。
  Widget _buildScope(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 用空串代表「全部」，避免 DropdownButton 对 null value 的歧义。
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '',
        child: Text(SearchStrings.scopeAll),
      ),
      for (final notebook in notebooks)
        DropdownMenuItem<String>(
          value: notebook.id,
          child: Text(notebook.name, overflow: TextOverflow.ellipsis),
        ),
    ];
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.filter_alt_outlined, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          if (notebooksLoading)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  SearchStrings.scopeLoading,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: selectedNotebookId ?? '',
                  isDense: true,
                  borderRadius: BorderRadius.circular(14),
                  items: items,
                  onChanged: (value) =>
                      onNotebookChanged(value == null || value.isEmpty ? null : value),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 弱化的小提示行（语义模式说明、笔记本列表降级说明）。
  Widget _hint(ColorScheme scheme, ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// 结果区：加载中 / 失败（带重试）/ 无结果 / 结果列表。
class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.async,
    required this.onRetry,
    required this.onOpen,
  });

  final AsyncValue<List<SearchHit>> async;
  final VoidCallback onRetry;
  final ValueChanged<SearchHit> onOpen;

  @override
  Widget build(BuildContext context) {
    return async.when(
      loading: () => const AppLoadingView(message: SearchStrings.searching),
      error: (error, _) => AppErrorView(
        message: _describeSearchError(error),
        title: error is ApiException && error.isUnauthorized
            ? SearchStrings.authErrorTitle
            : S.networkErrorTitle,
        onRetry: onRetry,
      ),
      data: (hits) => hits.isEmpty
          ? const AppEmptyView(
              icon: Icons.search_off_rounded,
              title: SearchStrings.emptyTitle,
              message: SearchStrings.emptyMessage,
            )
          : _ResultList(hits: hits, onOpen: onOpen),
    );
  }
}

/// 401 时额外提示去设置页检查访问密码。
String _describeSearchError(Object error) {
  final message = describeError(error);
  if (error is ApiException && error.isUnauthorized) {
    return '$message\n${SearchStrings.unauthorizedHint}';
  }
  return message;
}

class _ResultList extends StatelessWidget {
  const _ResultList({required this.hits, required this.onOpen});

  final List<SearchHit> hits;
  final ValueChanged<SearchHit> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: hits.length,
      itemBuilder: (context, index) {
        final hit = hits[index];
        // 同一笔记可能多次命中，用索引兜底保证 key 稳定且唯一。
        return _ResultTile(
          key: ValueKey<String>('search-hit-${hit.noteId}-$index'),
          hit: hit,
          onTap: () => onOpen(hit),
        );
      },
    );
  }
}

/// 单条搜索结果：标题 + 相关度（弱化展示）+ 可选正文摘要。
class _ResultTile extends StatelessWidget {
  const _ResultTile({super.key, required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = (hit.title ?? '').trim();
    final snippet = _snippet(hit.content);
    final relevance = hit.relevance;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        isThreeLine: snippet.isNotEmpty,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Text(
          title.isEmpty ? SearchStrings.unnamedNote : title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: snippet.isEmpty
            ? null
            : Text(
                snippet,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
        trailing: relevance == null
            ? null
            : Text(
                SearchStrings.relevance(relevance),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
      ),
    );
  }
}

/// 副标题摘要：压平换行与多余空白，超长截断，避免撑高列表。
String _snippet(String? content, {int maxLength = 120}) {
  final plain = (content ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (plain.isEmpty) return '';
  if (plain.length <= maxLength) return plain;
  return '${plain.substring(0, maxLength)}…';
}
