/// 初始化引导：部署预设（仅影响本地默认值与生成给服务器粘贴的 .env 片段）。
abstract final class SetupPreset {
  static const tencentLite = 'tencent_lite';
  static const dockerData = 'docker_data';
  static const custom = 'custom';

  static const ids = [tencentLite, dockerData, custom];

  static String label(String id) {
    return switch (id) {
      tencentLite => '腾讯轻量 / ubuntu 家目录',
      dockerData => '通用 Docker（/data）',
      custom => '自定义路径',
      _ => id,
    };
  }

  static String defaultBackupSource(String id) {
    return switch (id) {
      tencentLite => '/home/ubuntu/hermes-data',
      dockerData => '/data/hermes',
      custom => '',
      _ => '/home/ubuntu/hermes-data',
    };
  }

  static String defaultBackupDir(String id) {
    return switch (id) {
      tencentLite => '/home/ubuntu/hermes-backups',
      dockerData => '/data/hermes-backups',
      custom => '',
      _ => '/home/ubuntu/hermes-backups',
    };
  }
}
