import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfx/pdfx.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/chat/file_preview_kind.dart';
import '../../../core/ui/app_message.dart';
import '../../../core/chat/gateway_file_download.dart';
import '../../../core/chat/gateway_file_fetch.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/app_providers.dart';

/// 应用内预览 Gateway 文件（图片 / Markdown / HTML / PDF / CSV / 文本等）。
class FilePreviewPage extends ConsumerStatefulWidget {
  const FilePreviewPage({
    required this.url,
    this.title,
    super.key,
  });

  final String url;
  final String? title;

  static Future<void> open(
    BuildContext context, {
    required String url,
    String? title,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FilePreviewPage(url: url, title: title),
      ),
    );
  }

  @override
  ConsumerState<FilePreviewPage> createState() => _FilePreviewPageState();
}

class _FilePreviewPageState extends ConsumerState<FilePreviewPage> {
  GatewayFilePayload? _payload;
  FilePreviewKind? _kind;
  Object? _error;
  bool _loading = true;
  bool _downloading = false;
  PdfController? _pdfController;
  WebViewController? _htmlController;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  String? _htmlBaseUrl() {
    final uri = Uri.tryParse(widget.url);
    if (uri == null || uri.host.isEmpty) return null;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port/';
  }

  Future<void> _load() async {
    try {
      final api = ref.read(gatewayClientProvider);
      final payload = await fetchGatewayFileResilient(
        api.dio,
        widget.url,
        client: api,
        mediaFileName: widget.title,
      );
      if (!mounted) return;
      final kind = detectFilePreviewKind(
        url: widget.url,
        filename: payload.filename,
        contentType: payload.contentType,
      );
      PdfController? pdf;
      WebViewController? html;
      if (kind == FilePreviewKind.pdf) {
        pdf = PdfController(document: PdfDocument.openData(payload.bytes));
      } else if (kind == FilePreviewKind.html) {
        final htmlText = utf8.decode(payload.bytes, allowMalformed: true);
        html = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(htmlText, baseUrl: _htmlBaseUrl());
      }
      setState(() {
        _payload = payload;
        _kind = kind;
        _pdfController = pdf;
        _htmlController = html;
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  Future<void> _download() async {
    final payload = _payload;
    if (payload == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      await shareGatewayFile(payload);
      if (mounted) {
        AppMessage.success('已打开分享面板，可选择保存到本地');
      }
    } on Object catch (e) {
      if (mounted) {
        AppMessage.error('下载失败：$e');
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  String get _displayTitle {
    if (widget.title != null && widget.title!.trim().isNotEmpty) {
      return widget.title!.trim();
    }
    return _payload?.filename ?? '文件预览';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (_payload != null)
            IconButton(
              tooltip: '下载 / 分享',
              onPressed: _downloading ? null : _download,
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('无法预览：$_error', textAlign: TextAlign.center),
        ),
      );
    }
    final payload = _payload!;
    final kind = _kind ?? FilePreviewKind.binary;

    return switch (kind) {
      FilePreviewKind.image => _buildImage(payload),
      FilePreviewKind.markdown => _buildMarkdown(payload),
      FilePreviewKind.html => _buildHtml(),
      FilePreviewKind.pdf => _buildPdf(),
      FilePreviewKind.csv => _buildCsv(payload),
      FilePreviewKind.text => _buildText(payload),
      FilePreviewKind.binary => _buildBinary(payload),
    };
  }

  Widget _buildImage(GatewayFilePayload payload) {
    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 4,
      child: Center(
        child: Image.memory(payload.bytes, fit: BoxFit.contain),
      ),
    );
  }

  Widget _buildMarkdown(GatewayFilePayload payload) {
    final text = utf8.decode(payload.bytes, allowMalformed: true);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MarkdownBody(
          data: text,
          selectable: true,
          styleSheet: MarkdownStyleSheet(
            p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ),
      ),
    );
  }

  Widget _buildHtml() {
    final controller = _htmlController;
    if (controller == null) {
      return const Center(child: Text('HTML 加载失败'));
    }
    return WebViewWidget(controller: controller);
  }

  Widget _buildPdf() {
    final controller = _pdfController;
    if (controller == null) {
      return const Center(child: Text('PDF 加载失败'));
    }
    return PdfView(
      controller: controller,
      scrollDirection: Axis.vertical,
    );
  }

  Widget _buildCsv(GatewayFilePayload payload) {
    final raw = utf8.decode(payload.bytes, allowMalformed: true);
    final delimiter = widget.url.toLowerCase().contains('.tsv') ? '\t' : ',';
    List<List<dynamic>> rows;
    try {
      final parser = Csv(
        fieldDelimiter: delimiter,
        autoDetect: delimiter == ',',
        lineDelimiter: '\n',
      );
      rows = parser.decode(raw);
    } on Object {
      return _buildText(payload);
    }
    if (rows.isEmpty) {
      return const Center(child: Text('表格为空'));
    }

    final header = rows.first.map((c) => c.toString()).toList();
    final dataRows = rows.length > 1 ? rows.sublist(1) : <List<dynamic>>[];

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.all(12),
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(AppColors.grayLight.withValues(alpha: 0.35)),
            columns: header
                .map((h) => DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.w600))))
                .toList(),
            rows: dataRows
                .map(
                  (row) => DataRow(
                    cells: List.generate(
                      header.length,
                      (i) => DataCell(Text(i < row.length ? row[i].toString() : '')),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildText(GatewayFilePayload payload) {
    final text = utf8.decode(payload.bytes, allowMalformed: true);
    return Scrollbar(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.45),
        ),
      ),
    );
  }

  Widget _buildBinary(GatewayFilePayload payload) {
    final sizeKb = (payload.bytes.length / 1024).toStringAsFixed(1);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.insert_drive_file_outlined, size: 48, color: AppColors.gray),
            const SizedBox(height: 12),
            Text(payload.filename ?? '未知文件', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('大小约 $sizeKb KB\n当前类型暂不支持应用内预览', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _downloading ? null : _download,
              icon: const Icon(Icons.download_outlined),
              label: const Text('下载 / 分享'),
            ),
          ],
        ),
      ),
    );
  }
}
