/// 根据本地引导填写的内容，生成可粘贴到服务器 `~/gateway/.env` 的片段（不含真实 JWT，需你在服务器生成）。
String buildGatewayEnvSnippet({
  required String hermesApiOrigin,
  required String backupSource,
  required String backupDir,
}) {
  final api = hermesApiOrigin.trim();
  final src = backupSource.trim();
  final dir = backupDir.trim();
  return '''
NODE_ENV=production
PORT=3000
HOST=0.0.0.0

# 在服务器执行: openssl rand -hex 24  将结果填到下一行
JWT_SECRET=请替换为随机串至少8位

HERMES_API_ORIGIN=$api
HERMES_DASHBOARD_ORIGIN=http://172.18.0.1:9119
HERMES_API_SERVER_KEY=与宿主机 API_SERVER_KEY 一致
HERMES_DASHBOARD_TOKEN=hermes dashboard 启动日志中的 token

GATEWAY_AUTH_USER=syl
GATEWAY_AUTH_PASSWORD=请填写 App 登录密码

HERMES_BACKUP_SOURCE=$src
HERMES_BACKUP_DIR=$dir
HERMES_BACKUP_MAX=7
HERMES_DAILY_BACKUP_HOUR=2

GATEWAY_VERSION=0.1.0
'''
      .trim();
}
