/// 来源页文案。
///
/// 只放来源功能自己的文案；通用词（确定 / 取消 / 删除…）复用
/// `lib/ui/common/strings.dart` 的 `S`。
class SourcesStrings {
  const SourcesStrings._();

  // 列表
  static const String title = '来源';
  static const String allSources = '全部来源';
  static const String filterHint = '筛选来源标题或正文';
  static const String emptyTitle = '还没有来源';
  static const String emptyMessage = '添加网页链接、上传文件或粘贴一段文本，作为这个笔记本的知识来源。';
  static const String emptyAllTitle = '知识库里还没有来源';
  static const String emptyAllMessage = '先打开一个笔记本，再为它添加来源。';
  static const String filterEmptyTitle = '没有匹配的来源';
  static const String filterEmptyMessage = '换个关键词试试，或清空筛选条件。';
  static const String loadErrorTitle = '来源加载失败';
  static const String refresh = '刷新';
  static const String add = '添加来源';

  // 类型
  static const String typeLink = '链接';
  static const String typeText = '文本';
  static const String typeUpload = '文件';
  static const String typeLinkIcon = '网页链接';

  // 状态
  static const String statusProcessing = '处理中';
  static const String statusQueued = '排队中';
  static const String statusCompleted = '已完成';
  static const String statusFailed = '处理失败';
  static const String statusUnknown = '状态未知';
  static const String embedded = '已向量化';
  static const String notEmbedded = '未向量化';
  static const String retry = '重新处理';
  static const String retriedToast = '已重新提交处理';
  static const String failedDetailTitle = '处理失败的原因';

  // 元信息
  static const String updatedAt = '更新于';
  static const String topicsLabel = '主题';
  static const String insightsCount = '条洞见';
  static const String processingHint = '后端正在抽取正文与生成洞见，完成后会自动刷新';

  // 详情
  static const String detailTitle = '来源详情';
  static const String detailContent = '正文';
  static const String detailNoContent = '该来源还没有抽取到正文。';
  static const String detailInsights = '洞见';
  static const String detailNoInsights = '还没有洞见。添加来源时选择「洞见」类型即可生成。';
  static const String detailOpenLink = '在浏览器中打开';
  static const String detailOpenFailed = '无法打开该链接';
  static const String detailMeta = '信息';
  static const String detailKind = '类型';
  static const String detailCreated = '创建于';
  static const String detailChunks = '向量块';
  static const String detailFilePath = '后端路径';
  static const String detailNotebooks = '所属笔记本';

  // 删除 / 重命名
  static const String delete = '删除';
  static const String deleteTitle = '删除来源';
  static const String deletedToast = '来源已删除';
  static const String rename = '重命名';
  static const String renameTitle = '重命名来源';
  static const String renameHint = '输入新的来源标题';
  static const String renamedToast = '来源已重命名';

  static String deleteMessage(String title) =>
      '确定删除「$title」吗？来源正文、洞见与向量数据都会一并删除，操作不可恢复。';

  // 添加对话框
  static const String addTitle = '添加来源';
  static const String addSubtitle = '内容会交给 Open Notebook 后端抽取正文，并可生成洞见与向量索引。';
  static const String addKindLabel = '来源类型';
  static const String addTitleLabel = '标题';
  static const String addTitleHint = '给这个来源起个名字';
  static const String addTitleRequired = '请填写标题';
  static const String addUrlLabel = '链接地址';
  static const String addUrlHint = 'https://example.com/article\n每行一个链接可批量添加';
  static const String addUrlInvalid = '链接必须是 http 或 https 开头的地址';
  static const String addUrlRequired = '请填写链接地址';
  static const String addContentLabel = '正文';
  static const String addContentHint = '粘贴要保存为来源的文本内容…';
  static const String addContentRequired = '请填写正文';
  static const String addFileLabel = '文件';
  static const String addFileChoose = '选择文件';
  static const String addFileChange = '更换文件';
  static const String addFileRequired = '请先选择文件';
  static const String addNotebooksLabel = '加入笔记本';
  static const String addNotebooksEmpty = '还没有笔记本，可先创建一个再添加来源。';
  static const String addEmbedLabel = '生成向量索引';
  static const String addEmbedHint = '开启后可以用语义搜索/向量检索找到这个来源；需要后端配置嵌入模型。';
  static const String addSubmit = '添加';
  static const String addSubmitting = '正在提交…';
  static const String addProcessing = '后端正在处理…';
  static const String addProcessingHint = '抽取正文 / 生成洞见 / 构建向量索引可能需要几十秒，可关闭对话框稍后查看。';
  static const String addDone = '添加完成';
  static const String addFailed = '添加失败';
  static const String addBatchSummary = '来源已提交';
  static const String addClose = '关闭';
  static const String addBackground = '后台继续';
  static const String pickFileFailed = '选择文件失败';

  static String addFileSize(String size) => '大小 $size';
  static String batchCount(int count) => '共 $count 条链接';
  static String submittedCount(int done, int total) => '已提交 $done / $total';
  static String processingFailed(String message) => '处理失败：$message';
}
