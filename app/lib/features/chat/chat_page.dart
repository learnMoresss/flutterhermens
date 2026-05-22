import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/chat/approval_detect.dart';
import '../../core/ui/app_message.dart';
import '../../core/chat/chat_image_compress.dart';
import '../../core/chat/chat_message_metadata.dart';
import '../../core/chat/chat_shortcuts.dart';
import '../../core/chat/media_url_rewrite.dart';
import '../../core/chat/session_groups.dart';
import '../../core/chat/slash_commands.dart';
import '../../core/network/agent_admin_api.dart';
import '../../core/network/api_client.dart';
import '../../core/network/hermes_sessions_api.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/app_project_providers.dart';
import '../../providers/app_providers.dart';
import 'widgets/markdown_message_bubble.dart';
import 'widgets/slash_command_palette.dart';

const _userId = 'user';
const _assistantId = 'assistant';
const _maxTextFileBytes = 512 * 1024;
const _maxBinaryFileBytes = 8 * 1024 * 1024;
const _uploadThresholdBytes = 512 * 1024;

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  late final InMemoryChatController _chatController;
  late final TextEditingController _textController;
  final _users = <String, User>{
    _userId: const User(id: _userId, name: '我'),
    _assistantId: const User(id: _assistantId, name: 'Hermes'),
  };
  final _searchController = TextEditingController();
  final _imagePicker = ImagePicker();

  bool _isTyping = false;
  bool _isCompressingImage = false;
  bool _initialized = false;
  bool _sessionsLoading = false;
  bool _showShortcutChips = false;
  bool _showSlashPalette = false;
  bool _autoYoloPrefix = false;
  bool _createAppMode = false;
  bool _fastMode = false;
  String? _sessionsError;
  String? _activeSessionId;
  String? _activeSessionTitle;
  String? _selectedModel;
  String _slashQuery = '';
  String _usageSummary = '';
  List<HermesSessionSummary> _sessions = const [];
  List<HermesSavedModel> _models = const [];
  List<PendingChatImage> _pendingImages = const [];
  ({String name, String mimeType, String base64, bool isText})? _pendingFile;
  String _toolProgress = '';
  CancelToken? _streamCancelToken;
  bool _followBottom = true;
  bool _suppressAutoScroll = false;
  Timer? _scrollDebounce;
  ScrollController? _chatScrollControllerBacking;

  /// 惰性创建，避免 Hot Reload 后 `late` 未初始化。
  ScrollController get _chatScrollController {
    final existing = _chatScrollControllerBacking;
    if (existing != null) return existing;
    final created = ScrollController();
    created.addListener(_syncFollowBottomFromScroll);
    _chatScrollControllerBacking = created;
    return created;
  }

  HermesSessionsApi? _sessionsApi;
  AgentAdminApi? _agentApi;

  @override
  void initState() {
    super.initState();
    _chatController = InMemoryChatController();
    _textController = TextEditingController();
    _textController.addListener(_onComposerTextChanged);
  }

  void _onComposerTextChanged() {
    final text = _textController.text;
    final lastLine = text.split('\n').last;
    if (lastLine.startsWith('/') && !lastLine.contains(' ')) {
      if (!_showSlashPalette || _slashQuery != lastLine) {
        setState(() {
          _showSlashPalette = true;
          _slashQuery = lastLine;
        });
      }
    } else if (_showSlashPalette) {
      setState(() => _showSlashPalette = false);
    }
  }

  @override
  void dispose() {
    _scrollDebounce?.cancel();
    final scroll = _chatScrollControllerBacking;
    if (scroll != null) {
      scroll.removeListener(_syncFollowBottomFromScroll);
      scroll.dispose();
      _chatScrollControllerBacking = null;
    }
    _chatController.dispose();
    _textController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  ApiClient _client() => ref.read(gatewayClientProvider);

  void _closeDrawerIfOpen() {
    if (!mounted) return;
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen ?? false) {
      scaffold!.closeDrawer();
    }
  }

  /// 倒置列表：offset≈0 为最新消息（底部）。
  static const _bottomScrollThreshold = 72.0;

  void _syncFollowBottomFromScroll() {
    if (!_chatScrollController.hasClients || _suppressAutoScroll) return;
    final nearBottom = _chatScrollController.offset <= _bottomScrollThreshold;
    if (nearBottom != _followBottom) {
      _followBottom = nearBottom;
    }
  }

  bool get _isNearChatBottom {
    if (!_chatScrollController.hasClients) return _followBottom;
    return _chatScrollController.offset <= _bottomScrollThreshold;
  }

  void _onMessageContentExpanded(int messageIndex) {
    if (_suppressAutoScroll || !_followBottom || !_isNearChatBottom) return;
    final lastIndex = _chatController.messages.length - 1;
    if (messageIndex < lastIndex - 1) return;
    _scheduleScrollToBottom();
  }

  void _scheduleScrollToBottom({bool animated = false}) {
    if (_suppressAutoScroll || !_followBottom || !_isNearChatBottom) return;
    _scrollDebounce?.cancel();
    _scrollDebounce = Timer(const Duration(milliseconds: 120), () {
      if (mounted) {
        unawaited(_scrollChatToBottom(animated: animated));
      }
    });
  }

  Future<void> _scrollChatToBottom({bool animated = true}) async {
    if (!mounted || _suppressAutoScroll || !_followBottom) return;
    if (!_chatScrollController.hasClients) return;
    if (_chatScrollController.offset <= 4) return;

    const target = 0.0;
    if (animated) {
      await _chatScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    } else {
      _chatScrollController.jumpTo(target);
    }
  }

  Future<void> _rewriteAssistantMessagesInPlace(ApiClient client) async {
    for (final message in _chatController.messages) {
      if (!mounted) return;
      if (message.authorId != _assistantId || message is! TextMessage) continue;
      final text = message.text;
      if (!text.contains('file://') && !text.toUpperCase().contains('MEDIA:')) {
        continue;
      }
      final rewritten = await rewriteMediaUrlsAsync(text, client: client);
      if (!mounted) return;
      if (rewritten == text) continue;
      await _chatController.updateMessage(message, message.copyWith(text: rewritten));
    }
  }

  void _ensureClient() {
    final client = _client();
    _sessionsApi = HermesSessionsApi.fromClient(client);
    _agentApi = AgentAdminApi.fromClient(client);
  }

  Future<void> _loadModels() async {
    _ensureClient();
    try {
      final models = await _agentApi!.listModels();
      if (!mounted) return;
      setState(() {
        _models = models;
        if (_selectedModel == null && models.isNotEmpty) {
          _selectedModel = models.first.model;
        }
      });
    } on ApiException {
      // 模型列表可选，失败时仍可使用服务端默认模型
    }
  }

  Future<void> _persistActiveSession() async {
    final storage = ref.read(appStorageProvider);
    final id = _activeSessionId;
    if (id == null || id.isEmpty) {
      await storage.clearLastChatSession();
      return;
    }
    await storage.saveLastChatSession(
      id: id,
      title: _activeSessionTitle,
    );
  }

  Future<void> _restoreLastSessionIfAny() async {
    final storage = ref.read(appStorageProvider);
    final lastId = storage.lastChatSessionId;
    if (lastId == null || lastId.isEmpty) {
      await _startNewChat(silent: true);
      return;
    }

    HermesSessionSummary? match;
    for (final s in _sessions) {
      if (s.id == lastId) {
        match = s;
        break;
      }
    }

    if (match != null) {
      await _openSession(match, silent: true, fromRestore: true);
      return;
    }

    await _startNewChat(silent: true);
  }

  Future<void> _seedWelcome() async {
    if (_initialized) return;
    _initialized = true;
    _autoYoloPrefix = ref.read(appStorageProvider).autoYoloPrefix;
    _createAppMode = ref.read(appStorageProvider).createAppMode;
    _ensureClient();
    await _loadModels();
    await _refreshSessions(silent: true);
    await _restoreLastSessionIfAny();
  }

  Future<void> _refreshSessions({bool silent = false}) async {
    _ensureClient();
    if (!silent) setState(() => _sessionsLoading = true);
    try {
      final list = await _sessionsApi!.listSessions();
      if (mounted) {
        setState(() {
          _sessions = list;
          _sessionsError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _sessionsError = e.message);
    } finally {
      if (mounted && !silent) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _searchSessions(String query) async {
    _ensureClient();
    setState(() => _sessionsLoading = true);
    try {
      final list = query.trim().isEmpty
          ? await _sessionsApi!.listSessions()
          : await _sessionsApi!.searchSessions(query.trim());
      if (mounted) {
        setState(() {
          _sessions = list;
          _sessionsError = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _sessionsError = e.message);
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _startNewChat({bool silent = false}) async {
    setState(() {
      _activeSessionId = null;
      _activeSessionTitle = null;
      _pendingImages = const [];
      _pendingFile = null;
      _toolProgress = '';
    });
    _textController.clear();
    await _chatController.setMessages([
      Message.text(
        id: const Uuid().v4(),
        authorId: _assistantId,
        createdAt: DateTime.now(),
        text: chatNewChatText,
      ),
    ]);
    await _persistActiveSession();
    if (!silent && mounted) _closeDrawerIfOpen();
  }

  Future<void> _openSession(
    HermesSessionSummary session, {
    bool silent = false,
    bool fromRestore = false,
  }) async {
    _ensureClient();
    final client = _client();
    if (!silent) {
      setState(() {
        _activeSessionId = session.id;
        _activeSessionTitle = session.title;
        _sessionsLoading = true;
        _toolProgress = '';
        _pendingImages = const [];
        _pendingFile = null;
      });
    } else {
      _activeSessionId = session.id;
      _activeSessionTitle = session.title;
      _toolProgress = '';
      _pendingImages = const [];
      _pendingFile = null;
    }
    _textController.clear();
    try {
      final history = await _sessionsApi!.loadMessages(session.id);
      if (!mounted) return;
      final messages = <Message>[];
      for (final m in history) {
        if (m.content.trim().isEmpty) continue;
        final author = m.role == 'assistant' ? _assistantId : _userId;
        messages.add(
          Message.text(
            id: const Uuid().v4(),
            authorId: author,
            createdAt: m.createdAt ?? DateTime.now(),
            text: m.content,
          ),
        );
      }
      if (messages.isEmpty) {
        messages.add(
          Message.text(
            id: const Uuid().v4(),
            authorId: _assistantId,
            createdAt: DateTime.now(),
            text: '会话「${session.title}」暂无消息。',
          ),
        );
      }
      await _chatController.setMessages(messages);
      if (!mounted) return;
      setState(() {
        _activeSessionId = session.id;
        _activeSessionTitle = session.title;
        _followBottom = true;
      });
      await _persistActiveSession();
      if (!silent) _closeDrawerIfOpen();
      _suppressAutoScroll = true;
      try {
        await _rewriteAssistantMessagesInPlace(client);
      } finally {
        _suppressAutoScroll = false;
        if (mounted && _isNearChatBottom) _followBottom = true;
      }
    } on ApiException catch (e) {
      if (fromRestore && mounted) {
        await _startNewChat(silent: true);
      }
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _sessionsLoading = false);
    }
  }

  Future<void> _deleteSession(HermesSessionSummary session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除会话'),
        content: Text('确定删除「${session.title}」？此操作不可撤销。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定删除', style: TextStyle(color: Color(0xFFB00020))),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    _ensureClient();
    try {
      await _sessionsApi!.deleteSession(session.id);
      if (_activeSessionId == session.id) {
        await _startNewChat(silent: true);
      }
      await _refreshSessions();
      if (mounted) AppMessage.success('会话已删除');
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
  }

  Future<String> _uploadMediaUrl({
    required List<int> bytes,
    required String filename,
    required String mimeType,
  }) async {
    _ensureClient();
    final uploaded = await _client().uploadFile(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
    );
    final url = uploaded.url?.trim();
    if (url != null && url.isNotEmpty) return url;
    throw ApiException(
      '「$filename」已上传，但 Gateway 未返回公网 URL（请配置 GATEWAY_PUBLIC_BASE_URL）',
    );
  }

  Future<void> _addCompressedPendingImage({
    required Uint8List bytes,
    String? sourcePath,
    String filename = 'image.jpg',
  }) async {
    if (_isCompressingImage) return;
    setState(() => _isCompressingImage = true);
    try {
      final compressed = await ChatImageCompressor.compress(
        input: bytes,
        filePath: sourcePath,
        filename: filename,
      );
      final url = await _uploadMediaUrl(
        bytes: compressed.bytes,
        filename: compressed.filename,
        mimeType: compressed.mimeType,
      );
      if (!mounted) return;
      setState(() {
        _pendingImages = [
          ..._pendingImages,
          PendingChatImage(
            mimeType: compressed.mimeType,
            url: url,
            previewBytes: Uint8List.fromList(compressed.bytes),
          ),
        ];
      });
    } on ChatImageTooLargeException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    } finally {
      if (mounted) setState(() => _isCompressingImage = false);
    }
  }

  Future<void> _pickImage() async {
    if (_isCompressingImage) return;
    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxBinaryFileBytes) {
      if (mounted) {
        AppMessage.warning('图片过大（最大 ${_maxBinaryFileBytes ~/ 1024 ~/ 1024}MB）');
      }
      return;
    }
    await _addCompressedPendingImage(
      bytes: bytes,
      sourcePath: file.path,
      filename: 'image.jpg',
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return;

    final mime = _guessMime(f.extension, f.name);
    final isText = _isTextMime(mime) || _isTextMime(f.extension ?? '');
    final max = isText ? _maxTextFileBytes : _maxBinaryFileBytes;
    if (bytes.length > max) {
      if (mounted) {
        AppMessage.warning('文件过大（最大 ${max ~/ 1024}KB）');
      }
      return;
    }

    try {
      if (mime.startsWith('image/')) {
        await _addCompressedPendingImage(
          bytes: bytes,
          sourcePath: f.path,
          filename: f.name,
        );
        return;
      }

      final String b64;
      if (isText && bytes.length <= _uploadThresholdBytes) {
        b64 = base64Encode(bytes);
      } else {
        throw ApiException('「${f.name}」请使用图片格式，或选择较小的文本文件');
      }
      setState(() {
        _pendingFile = (
          name: f.name,
          mimeType: mime,
          base64: b64,
          isText: isText,
        );
      });
    } on ApiException catch (e) {
      if (mounted) {
        AppMessage.error(e.message);
      }
    }
  }

  String _guessMime(String? ext, String name) {
    final e = (ext ?? name.split('.').lastOrNull ?? '').toLowerCase();
    const map = {
      'png': 'image/png',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'md': 'text/markdown',
      'json': 'application/json',
    };
    return map[e] ?? 'application/octet-stream';
  }

  bool _isTextMime(String mime) {
    final m = mime.toLowerCase();
    return m.startsWith('text/') ||
        m == 'application/json' ||
        m == 'application/xml' ||
        m.endsWith('markdown');
  }

  void _applySlashCommand(SlashCommand cmd) {
    final text = _textController.text;
    final lines = text.split('\n');
    lines[lines.length - 1] = '${cmd.name} ';
    _textController.text = lines.join('\n');
    _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    setState(() => _showSlashPalette = false);
  }

  Future<void> _showSlashHelpDialog() async {
    final grouped = <SlashCommandCategory, List<SlashCommand>>{};
    for (final cmd in allSlashCommands) {
      grouped.putIfAbsent(cmd.category, () => []).add(cmd);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('斜杠命令'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final entry in grouped.entries) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    slashCommandCategoryLabels[entry.key] ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                for (final cmd in entry.value)
                  ListTile(
                    dense: true,
                    title: Text(cmd.name, style: const TextStyle(fontFamily: 'monospace')),
                    subtitle: Text(cmd.description),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭')),
        ],
      ),
    );
  }

  Future<void> _runLocalSlashCommand(SlashCommand cmd, String raw) async {
    switch (cmd.name) {
      case '/new':
        await _startNewChat(silent: true);
        return;
      case '/clear':
        await _chatController.setMessages([
          Message.text(
            id: const Uuid().v4(),
            authorId: _assistantId,
            createdAt: DateTime.now(),
            text: '对话已清空。继续输入即可。',
          ),
        ]);
        return;
      case '/fast':
        setState(() => _fastMode = !_fastMode);
        if (mounted) {
          AppMessage.info(_fastMode ? '已开启优先模式（低延迟）' : '已关闭优先模式');
        }
        return;
      case '/usage':
        if (_usageSummary.isEmpty) {
          AppMessage.info('暂无用量数据，请先完成一轮对话');
        } else {
          AppMessage.info(_usageSummary);
        }
        return;
      case '/help':
        await _showSlashHelpDialog();
        return;
      case '/model':
        await _insertLocalInfo(await _fetchModelInfo());
        return;
      case '/memory':
        await _insertLocalInfo(await _fetchMemoryInfo());
        return;
      case '/tools':
        await _insertLocalInfo(await _fetchToolsInfo());
        return;
      case '/skills':
        await _insertLocalInfo(await _fetchSkillsInfo());
        return;
      case '/persona':
        await _insertLocalInfo(await _fetchPersonaInfo());
        return;
      case '/version':
        await _insertLocalInfo(await _fetchVersionInfo());
        return;
      default:
        return;
    }
  }

  Future<void> _insertLocalInfo(String text) async {
    if (!mounted) return;
    await _chatController.insertMessage(
      Message.text(
        id: const Uuid().v4(),
        authorId: _assistantId,
        createdAt: DateTime.now(),
        text: text,
      ),
    );
  }

  Future<String> _fetchModelInfo() async {
    _ensureClient();
    try {
      final api = AgentAdminApi.fromClient(_client());
      final p = await api.listProviders();
      return '**当前模型**\n\n'
          '- 提供商：`${p.provider.isEmpty ? '未设置' : p.provider}`\n'
          '- 模型：`${p.model.isEmpty ? '未设置' : p.model}`\n'
          '${p.baseUrl.isNotEmpty ? '- Base URL：${p.baseUrl}\n' : ''}';
    } on ApiException catch (e) {
      return '无法读取模型配置：${e.message}';
    }
  }

  Future<String> _fetchMemoryInfo() async {
    _ensureClient();
    try {
      final api = AgentAdminApi.fromClient(_client());
      final mem = await api.getMemory();
      final lines = <String>['**Agent 记忆**\n'];
      if (mem.memoryEntries.isEmpty) {
        lines.add('暂无记忆条目。');
      } else {
        for (final e in mem.memoryEntries.take(8)) {
          lines.add('- ${e.content}');
        }
      }
      lines.add('\n**统计**：${mem.totalSessions} 个会话，${mem.totalMessages} 条消息');
      return lines.join('\n');
    } on ApiException catch (e) {
      return '无法读取记忆：${e.message}';
    }
  }

  Future<String> _fetchToolsInfo() async {
    _ensureClient();
    try {
      final api = AgentAdminApi.fromClient(_client());
      final tools = await api.listToolsets();
      if (tools.isEmpty) return '**工具集**\n\n暂无工具集。';
      final rows = tools
          .map((t) => '- **${t.label}**：${t.description} ${t.enabled ? '（已启用）' : '（已禁用）'}')
          .join('\n');
      return '**可用工具集**\n\n$rows';
    } on ApiException catch (e) {
      return '无法读取工具集：${e.message}';
    }
  }

  Future<String> _fetchSkillsInfo() async {
    _ensureClient();
    try {
      final api = AgentAdminApi.fromClient(_client());
      final skills = await api.listSkills();
      if (skills.isEmpty) return '**已安装技能**\n\n暂无技能。';
      final rows = skills.map((s) => '- **${s.name}**（${s.category}）').join('\n');
      return '**已安装技能**\n\n$rows';
    } on ApiException catch (e) {
      return '无法读取技能：${e.message}';
    }
  }

  Future<String> _fetchPersonaInfo() async {
    _ensureClient();
    try {
      final api = AgentAdminApi.fromClient(_client());
      final soul = await api.getSoul();
      return soul.trim().isEmpty ? '**人格设定**\n\nSOUL.md 为空。' : '**人格设定 (SOUL.md)**\n\n$soul';
    } on ApiException catch (e) {
      return '无法读取人格：${e.message}';
    }
  }

  Future<String> _fetchVersionInfo() async {
    _ensureClient();
    try {
      final health = await _client().healthCheck();
      final api = AgentAdminApi.fromClient(_client());
      final status = await api.getStatus();
      return '**版本信息**\n\n'
          '- Gateway：${health['gatewayVersion'] ?? health['status'] ?? 'ok'}\n'
          '- Hermes Home：`${status['hermesHome'] ?? '—'}`';
    } on ApiException catch (e) {
      return '无法读取版本：${e.message}';
    }
  }

  Future<void> _renameSession(HermesSessionSummary session) async {
    _ensureClient();
    final ctrl = TextEditingController(text: session.title);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('重命名会话'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(labelText: '标题')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    try {
      await _sessionsApi!.updateSessionTitle(session.id, ctrl.text.trim());
      await _refreshSessions(silent: true);
      if (_activeSessionId == session.id) {
        setState(() => _activeSessionTitle = ctrl.text.trim());
      }
    } on ApiException catch (e) {
      if (mounted) AppMessage.error(e.message);
    }
    ctrl.dispose();
  }

  void _stopGeneration() {
    _streamCancelToken?.cancel('用户停止');
  }

  Future<void> _pickModel() async {
    if (_models.isEmpty) {
      await _loadModels();
    }
    if (!mounted) return;
    if (_models.isEmpty) {
      AppMessage.info('暂无可用模型，将使用服务端默认模型');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择模型', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _models.length,
                itemBuilder: (context, index) {
                  final m = _models[index];
                  final selected = m.model == _selectedModel;
                  return ListTile(
                    selected: selected,
                    title: Text(m.displayLabel),
                    subtitle: Text('${m.provider} · ${m.model}', maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => Navigator.pop(context, m.model),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedModel = picked);
    }
  }

  void _insertShortcut(ChatShortcut shortcut) {
    if (shortcut.action == ChatShortcutAction.newChat) {
      _startNewChat(silent: true);
      return;
    }
    if (shortcut.action == ChatShortcutAction.createAppMode) {
      _toggleCreateAppMode(!_createAppMode);
      return;
    }
    final text = shortcut.insertText;
    if (text == null) return;
    final current = _textController.text;
    final prefix = current.isEmpty ? '' : (current.endsWith('\n') ? '' : '\n');
    _textController.text = '$current$prefix$text ';
    _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
  }

  Future<void> _toggleAutoYolo(bool value) async {
    await ref.read(appStorageProvider).setAutoYoloPrefix(value);
    setState(() => _autoYoloPrefix = value);
    if (mounted) {
      AppMessage.info(value ? '已开启：发送时自动附带 /yolo' : '已关闭自动 /yolo');
    }
  }

  Future<void> _toggleCreateAppMode(bool value) async {
    await ref.read(appStorageProvider).setCreateAppMode(value);
    setState(() => _createAppMode = value);
    if (mounted) {
      AppMessage.info(
        value
            ? '已开启「创建 App」：每条消息将由 Gateway 强制注入 create-app 完整 SKILL'
            : '已关闭「创建 App」模式',
      );
    }
  }

  Future<void> _showComposerMoreSheet() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Text('聊天选项', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                SwitchListTile(
                  title: const Text('优先模式'),
                  subtitle: const Text('低延迟响应'),
                  value: _fastMode,
                  onChanged: _isTyping
                      ? null
                      : (v) {
                          setState(() => _fastMode = v);
                          AppMessage.info(v ? '已开启优先模式（低延迟）' : '已关闭优先模式');
                          Navigator.pop(ctx);
                        },
                ),
                SwitchListTile(
                  title: const Text('创建 App'),
                  subtitle: const Text('Gateway 强制注入 create-app 完整 SKILL'),
                  value: _createAppMode,
                  onChanged: _isTyping
                      ? null
                      : (v) {
                          Navigator.pop(ctx);
                          unawaited(_toggleCreateAppMode(v));
                        },
                ),
                SwitchListTile(
                  title: const Text('自动 /yolo'),
                  subtitle: const Text('发送时自动在消息前附带 /yolo'),
                  value: _autoYoloPrefix,
                  onChanged: _isTyping
                      ? null
                      : (v) {
                          Navigator.pop(ctx);
                          unawaited(_toggleAutoYolo(v));
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  ChatTheme get _chatTheme => ChatTheme(
        colors: const ChatColors(
          primary: AppColors.black,
          onPrimary: AppColors.white,
          surface: AppColors.white,
          onSurface: AppColors.black,
          surfaceContainerLow: AppColors.surface,
          surfaceContainer: AppColors.surface,
          surfaceContainerHigh: AppColors.grayLight,
        ),
        typography: ChatTypography.standard(),
        shape: const BorderRadius.all(Radius.circular(4)),
      );

  Future<User?> _resolveUser(UserID id) async => _users[id];

  List<Map<String, dynamic>> _buildApiMessages() {
    final out = <Map<String, dynamic>>[];
    for (final msg in _chatController.messages) {
      if (msg is! TextMessage) continue;
      if (msg.text == kHermesLoadingText) continue;
      if (msg.text.trim().isEmpty && !hasChatAttachments(msg.metadata)) continue;
      if (msg.authorId == _assistantId && isUiOnlyAssistantText(msg.text)) continue;
      final role = msg.authorId == _userId ? 'user' : 'assistant';
      final images = parseChatImages(msg.metadata);
      if (role == 'user' && images.isNotEmpty) {
        out.add({
          'role': role,
          'content': ApiClient.buildUserContent(
            text: msg.text,
            images: images.map((img) => img.toApiPayload()).toList(growable: false),
          ),
        });
      } else {
        out.add({'role': role, 'content': msg.text});
      }
    }
    return out;
  }

  String _composeSendText(String trimmed) {
    if (_autoYoloPrefix && trimmed.isNotEmpty && !trimmed.startsWith('/yolo')) {
      return '/yolo\n$trimmed';
    }
    return trimmed;
  }

  Future<void> _handleSend(String text) async {
    var trimmed = text.trim();
    final slashOnly = matchSlashCommand(trimmed);
    if (slashOnly?.local == true && _pendingImages.isEmpty && _pendingFile == null) {
      _textController.clear();
      setState(() => _showSlashPalette = false);
      await _runLocalSlashCommand(slashOnly!, trimmed);
      return;
    }

    trimmed = _composeSendText(trimmed);
    final hasImages = _pendingImages.isNotEmpty;
    final hasFile = _pendingFile != null;
    if ((trimmed.isEmpty && !hasImages && !hasFile) || _isTyping) return;

    _ensureClient();
    _streamCancelToken = CancelToken();

    final images = List.of(_pendingImages);
    final file = _pendingFile;
    final displayText = trimmed;
    final attachmentImages = images.map((img) => img.toAttachment()).toList(growable: false);
    final attachmentFile = hasFile
        ? ChatFileAttachment(name: file!.name, mimeType: file.mimeType)
        : null;

    await _chatController.insertMessage(
      Message.text(
        id: const Uuid().v4(),
        authorId: _userId,
        createdAt: DateTime.now(),
        text: displayText,
        metadata: buildChatAttachmentsMetadata(
          images: attachmentImages,
          file: attachmentFile,
        ),
      ),
    );
    _followBottom = true;

    setState(() {
      _isTyping = true;
      _pendingImages = const [];
      _pendingFile = null;
      _toolProgress = '';
    });
    _textController.clear();

    final apiMessages = _buildApiMessages();
    if (apiMessages.isNotEmpty) {
      final last = apiMessages.last;
      if (last['role'] == 'user') {
        last['content'] = ApiClient.buildUserContent(
          text: trimmed,
          images: images.isEmpty ? null : images.map((img) => img.toApiPayload()).toList(growable: false),
          files: file == null ? null : [file],
        );
      }
    }

    final assistantMessageId = const Uuid().v4();
    var assistantMessage = Message.text(
      id: assistantMessageId,
      authorId: _assistantId,
      createdAt: DateTime.now(),
      text: kHermesLoadingText,
    );
    await _chatController.insertMessage(assistantMessage);

    final buffer = StringBuffer();
    try {
      await _client().streamChat(
        messages: apiMessages,
        sessionId: _activeSessionId,
        model: _selectedModel,
        cancelToken: _streamCancelToken,
        createAppMode: _createAppMode,
        targetProjectSlug:
            _createAppMode ? ref.read(activeViewingProjectSlugProvider) : null,
        onSessionId: (sid) {
          if (mounted && sid.isNotEmpty) {
            setState(() => _activeSessionId = sid);
            _persistActiveSession();
          }
        },
        onEvent: (event) {
          if (event is ChatToolProgress) {
            setState(() => _toolProgress = event.detail);
            return;
          }
          if (event is ChatUsageStats) {
            final cost = event.cost != null ? ' · 约 ${event.cost!.toStringAsFixed(4)} 美元' : '';
            setState(() {
              _usageSummary =
                  'Token：输入 ${event.promptTokens} / 输出 ${event.completionTokens} / 合计 ${event.totalTokens}$cost';
            });
            return;
          }
          if (event is ChatTextDelta) {
            buffer.write(event.text);
            final current = assistantMessage;
            if (current is! TextMessage) return;
            var textOut = rewriteMediaUrlsLite(buffer.toString());
            if (_toolProgress.isNotEmpty) {
              textOut = '⏳ $_toolProgress\n\n$textOut';
            }
            final updated = current.copyWith(text: textOut.isEmpty ? kHermesLoadingText : textOut);
            _chatController.updateMessage(current, updated);
            assistantMessage = updated;
            if (_followBottom && _isNearChatBottom) {
              _scheduleScrollToBottom();
            }
          }
        },
      );

      final current = assistantMessage;
      if (current is TextMessage && buffer.isNotEmpty) {
        if (mounted) {
          final client = _client();
          var finalized = await rewriteMediaUrlsAsync(buffer.toString(), client: client);
          if (!mounted) return;
          if (_toolProgress.isNotEmpty) {
            finalized = '⏳ $_toolProgress\n\n$finalized';
          }
          final updated = current.copyWith(text: finalized);
          await _chatController.updateMessage(current, updated);
        }
      } else if (current is TextMessage && buffer.isEmpty) {
        final updated = current.copyWith(text: '（空响应）');
        await _chatController.updateMessage(current, updated);
      }
      await _refreshSessions(silent: true);
      if (_activeSessionId != null) {
        final sid = _activeSessionId!;
        final match = _sessions.where((s) => s.id == sid).firstOrNull;
        if (match != null && mounted) {
          setState(() => _activeSessionTitle = match.title);
        }
        await _persistActiveSession();
      }
    } on ApiException catch (e) {
      final current = assistantMessage;
      if (current is TextMessage) {
        final msg = e.message == '已停止生成' ? '（已停止）' : '请求失败：${e.message}';
        final updated = current.copyWith(text: msg);
        await _chatController.updateMessage(current, updated);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isTyping = false;
          _toolProgress = '';
          _streamCancelToken = null;
        });
      }
    }
  }

  void _removePendingImage(int index) {
    setState(() {
      final next = List.of(_pendingImages)..removeAt(index);
      _pendingImages = next;
    });
  }

  Widget _buildPendingAttachments() {
    if (_pendingImages.isEmpty && _pendingFile == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < _pendingImages.length; i++)
                _PendingAttachmentChip(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.memory(
                      _pendingImages[i].previewBytes,
                      width: 72,
                      height: 72,
                      fit: BoxFit.cover,
                    ),
                  ),
                  onRemove: () => _removePendingImage(i),
                ),
              if (_pendingFile != null)
                _PendingAttachmentChip(
                  child: Container(
                    width: 72,
                    height: 72,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.grayLight.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.insert_drive_file_outlined, size: 22),
                        const SizedBox(height: 4),
                        Text(
                          _pendingFile!.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  onRemove: () => setState(() => _pendingFile = null),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComposerToolbar() {
    return ColoredBox(
      color: AppColors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildPendingAttachments(),
          const Divider(height: 1, thickness: 1, color: AppColors.grayLight),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
            child: Row(
              children: [
                IconButton(
                  tooltip: '选择图片',
                  visualDensity: VisualDensity.compact,
                  onPressed: (_isTyping || _isCompressingImage) ? null : _pickImage,
                  icon: Badge(
                    isLabelVisible: _pendingImages.isNotEmpty,
                    label: Text('${_pendingImages.length}'),
                    child: const Icon(Icons.image_outlined, size: 22),
                  ),
                ),
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '选择文件',
                  visualDensity: VisualDensity.compact,
                  onPressed: (_isTyping || _isCompressingImage) ? null : _pickFile,
                  icon: Badge(
                    isLabelVisible: _pendingFile != null,
                    label: const Text('1'),
                    child: const Icon(Icons.attach_file, size: 22),
                  ),
                ),
                if (_isCompressingImage) ...[
                  const SizedBox(width: 4),
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
                const SizedBox(width: 2),
                IconButton(
                  tooltip: '快捷指令',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _showShortcutChips = !_showShortcutChips),
                  icon: Icon(
                    _showShortcutChips ? Icons.keyboard_arrow_down : Icons.bolt_outlined,
                    size: 22,
                  ),
                ),
                if (_isTyping) ...[
                  const SizedBox(width: 2),
                  IconButton(
                    tooltip: '停止生成',
                    visualDensity: VisualDensity.compact,
                    onPressed: _stopGeneration,
                    icon: const Icon(Icons.stop_circle_outlined, size: 22, color: Colors.red),
                  ),
                ],
                const Spacer(),
                if (_fastMode || _createAppMode || _autoYoloPrefix)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.grayLight.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        [
                          if (_fastMode) '优先',
                          if (_createAppMode) 'App',
                          if (_autoYoloPrefix) '/yolo',
                        ].join(' · '),
                        style: const TextStyle(fontSize: 10, color: AppColors.gray),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '更多选项',
                  visualDensity: VisualDensity.compact,
                  onPressed: _showComposerMoreSheet,
                  icon: Badge(
                    isLabelVisible: _fastMode || _createAppMode || _autoYoloPrefix,
                    child: const Icon(Icons.more_horiz, size: 22),
                  ),
                ),
              ],
            ),
          ),
          if (_showSlashPalette)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: SlashCommandPalette(
                commands: filterSlashCommands(_slashQuery),
                onSelect: _applySlashCommand,
              ),
            ),
          if (_showShortcutChips)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: defaultChatShortcuts
                    .map(
                      (s) => ActionChip(
                        label: Text(s.label, style: const TextStyle(fontSize: 12)),
                        onPressed: _isTyping ? null : () => _insertShortcut(s),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('会话', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(tooltip: '新建对话', onPressed: () => _startNewChat(), icon: const Icon(Icons.add)),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _sessionsLoading ? null : () => _refreshSessions(),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索会话…',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(4)),
                ),
                onSubmitted: _searchSessions,
              ),
            ),
            TextButton(
              onPressed: () => context.push('/home/chat/sessions'),
              child: const Text('查看全部会话'),
            ),
            if (_sessionsError != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_sessionsError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              ),
            Expanded(
              child: _sessionsLoading && _sessions.isEmpty
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : Builder(
                      builder: (context) {
                        final grouped = groupSessions(_sessions);
                        final tiles = <Widget>[];
                        for (final group in SessionDateGroup.values) {
                          final items = grouped[group]!;
                          if (items.isEmpty) continue;
                          tiles.add(
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: Text(
                                sessionDateGroupLabels[group] ?? '',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.gray,
                                ),
                              ),
                            ),
                          );
                          for (final s in items) {
                            final selected = s.id == _activeSessionId;
                            tiles.add(
                              ListTile(
                                selected: selected,
                                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  s.snippet ?? s.preview ?? '${s.messageCount} 条消息',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                onTap: () => _openSession(s),
                                onLongPress: () => _renameSession(s),
                                trailing: IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _deleteSession(s),
                                ),
                              ),
                            );
                          }
                        }
                        if (tiles.isEmpty) {
                          return const Center(child: Text('暂无会话', style: TextStyle(color: AppColors.gray)));
                        }
                        return ListView(children: tiles);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _seedWelcome();

    final title = _activeSessionTitle ?? '新对话';
    final modelLabel = _selectedModel ?? '默认模型';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (_usageSummary.isNotEmpty)
              Text(
                _usageSummary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.gray, fontSize: 11),
              ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _isTyping ? null : _pickModel,
            icon: const Icon(Icons.layers_outlined, size: 18),
            label: Text(
              modelLabel.length > 18 ? '${modelLabel.substring(0, 18)}…' : modelLabel,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.grayLight),
        ),
      ),
      body: MediaQuery.removePadding(
        context: context,
        removeBottom: true,
        child: Chat(
          currentUserId: _userId,
          resolveUser: _resolveUser,
          chatController: _chatController,
          theme: _chatTheme,
          backgroundColor: AppColors.white,
          onMessageSend: _handleSend,
          builders: Builders(
            chatAnimatedListBuilder: (context, itemBuilder) => NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification ||
                    notification is ScrollEndNotification) {
                  _syncFollowBottomFromScroll();
                }
                return false;
              },
              child: ChatAnimatedListReversed(
                scrollController: _chatScrollController,
                itemBuilder: itemBuilder,
                scrollToEndAnimationDuration: const Duration(milliseconds: 180),
                shouldScrollToEndWhenSendingMessage: true,
              ),
            ),
            textMessageBuilder: (context, message, index, {required isSentByMe, groupStatus}) {
              final needsApproval = !isSentByMe && messageNeedsApproval(message.text);
              return MarkdownMessageBubble(
                message: message,
                index: index,
                isSentByMe: isSentByMe,
                showApproval: needsApproval && !_isTyping,
                onApprove: needsApproval ? () => _handleSend('/approve') : null,
                onDeny: needsApproval ? () => _handleSend('/deny') : null,
                onContentExpanded: () => _onMessageContentExpanded(index),
              );
            },
            composerBuilder: (context) => Composer(
              textEditingController: _textController,
              topWidget: _buildComposerToolbar(),
              handleSafeArea: false,
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
              sigmaX: 0,
              sigmaY: 0,
              hintText: '输入消息…',
              sendOnEnter: true,
              textInputAction: TextInputAction.send,
              sendButtonDisabled: _isTyping,
              inputBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(4)),
                borderSide: BorderSide(color: AppColors.grayLight, width: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({required this.child, required this.onRemove});

  final Widget child;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          Positioned(
            top: -6,
            right: -6,
            child: Material(
              color: AppColors.black,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(2),
                  child: Icon(Icons.close, size: 14, color: AppColors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
