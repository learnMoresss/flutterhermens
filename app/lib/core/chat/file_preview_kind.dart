import 'gateway_file_fetch.dart';

enum FilePreviewKind {
  image,
  markdown,
  html,
  pdf,
  csv,
  text,
  binary,
}

FilePreviewKind detectFilePreviewKind({
  required String url,
  String? filename,
  String? contentType,
}) {
  final name = (filename ?? filenameFromGatewayUrl(url) ?? '').toLowerCase();
  final ct = (contentType ?? '').toLowerCase();

  if (_isImage(name, ct)) return FilePreviewKind.image;
  if (_isPdf(name, ct)) return FilePreviewKind.pdf;
  if (_isHtml(name, ct)) return FilePreviewKind.html;
  if (_isMarkdown(name, ct)) return FilePreviewKind.markdown;
  if (_isCsv(name, ct)) return FilePreviewKind.csv;
  if (_isText(name, ct)) return FilePreviewKind.text;
  return FilePreviewKind.binary;
}

bool _isImage(String name, String ct) {
  return ct.startsWith('image/') ||
      name.endsWith('.png') ||
      name.endsWith('.jpg') ||
      name.endsWith('.jpeg') ||
      name.endsWith('.gif') ||
      name.endsWith('.webp') ||
      name.endsWith('.svg') ||
      name.endsWith('.bmp') ||
      name.endsWith('.avif');
}

bool _isPdf(String name, String ct) {
  return ct.contains('pdf') || name.endsWith('.pdf');
}

bool _isHtml(String name, String ct) {
  return ct.contains('html') || name.endsWith('.html') || name.endsWith('.htm');
}

bool _isMarkdown(String name, String ct) {
  return ct.contains('markdown') ||
      name.endsWith('.md') ||
      name.endsWith('.markdown');
}

bool _isCsv(String name, String ct) {
  return ct.contains('csv') ||
      name.endsWith('.csv') ||
      name.endsWith('.tsv');
}

bool _isText(String name, String ct) {
  return ct.startsWith('text/') ||
      name.endsWith('.txt') ||
      name.endsWith('.json') ||
      name.endsWith('.xml') ||
      name.endsWith('.log') ||
      name.endsWith('.yaml') ||
      name.endsWith('.yml');
}
