/// 与网关 `HERMES_ORIGIN` 解析约定一致（见 gateway/src/hermes-origin-env.ts）。
const int kHermesDefaultListenPort = 8080;

bool isHermesOriginGatewayToken(String raw) {
  final s = raw.trim().toLowerCase();
  return s == 'auto' || s == 'detect' || s == 'docker-host' || s == 'docker-bridge';
}

/// 裸 IPv4（网关会补全为 http://IP:端口）
bool isBareIpv4(String raw) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(raw.trim());

/// host:port 且无 scheme（网关会补全 http://）
bool isHostPortWithoutScheme(String raw) {
  final t = raw.trim();
  return RegExp(r'^[\w.-]+:\d+$').hasMatch(t) && !t.contains('://');
}

/// 初始化引导里「Hermes 根地址」校验：完整 URL 或网关支持的简写。
String? validateHermesOriginForSetup(String? value) {
  final input = value?.trim() ?? '';
  if (input.isEmpty) {
    return '请填写 Hermes 根地址（可填 auto、docker-host、裸 IP 或完整 http(s) URL）';
  }
  if (isHermesOriginGatewayToken(input)) return null;
  if (isBareIpv4(input)) return null;
  if (isHostPortWithoutScheme(input)) return null;
  final uri = Uri.tryParse(input);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return '请输入有效 URL，或 auto / docker-host / 裸 IPv4';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return '仅支持 http 或 https';
  }
  return null;
}
