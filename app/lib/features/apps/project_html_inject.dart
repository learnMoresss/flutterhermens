import 'dart:convert';

/// 与 Gateway [`project-html-inject.ts`] 一致的 HTML 注入。
String injectHermesProjectHtml(String html, String slug, String gatewayBase) {
  final base = gatewayBase.replaceAll(RegExp(r'/$'), '');
  final projectMeta = jsonEncode({
    'slug': slug,
    'apiBase': '/v1/projects/$slug/api',
    'hostApi': '/v1/hermes-app/host.js',
  });
  final hostSrc = '$base/v1/hermes-app/host.js';
  final inject =
      '<script>window.__HERMES_PROJECT__=$projectMeta;</script>'
      '<script src="$hostSrc"></script>';
  if (html.contains('</head>')) {
    return html.replaceFirst('</head>', '$inject</head>');
  }
  return inject + html;
}

/// 服务器端 HTML 已知损坏时，App 内嵌 bundle 覆盖（待 Gateway 同步后可移除 slug）。
const bundledProjectHtmlSlugs = {'image-compressor'};

String bundledProjectAssetPath(String slug) => 'assets/projects/$slug/index.html';
