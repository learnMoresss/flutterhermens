import 'package:dio/dio.dart';

import 'api_client.dart';

class HermesCronJob {
  const HermesCronJob({
    required this.id,
    required this.name,
    required this.schedule,
    required this.prompt,
    required this.state,
    required this.enabled,
    this.nextRunAt,
    this.lastRunAt,
    this.lastStatus,
    this.lastError,
    this.deliver = const ['local'],
  });

  final String id;
  final String name;
  final String schedule;
  final String prompt;
  final String state;
  final bool enabled;
  final String? nextRunAt;
  final String? lastRunAt;
  final String? lastStatus;
  final String? lastError;
  final List<String> deliver;

  factory HermesCronJob.fromJson(Map<String, dynamic> json) {
    final enabled = json['enabled'] != false;
    var state = (json['state'] ?? 'active').toString();
    if (!enabled) state = 'paused';

    final scheduleRaw = json['schedule'];
    String scheduleText = '?';
    if (json['schedule_display'] != null) {
      scheduleText = json['schedule_display'].toString();
    } else if (scheduleRaw is Map && scheduleRaw['value'] != null) {
      scheduleText = scheduleRaw['value'].toString();
    } else if (scheduleRaw != null) {
      scheduleText = scheduleRaw.toString();
    }

    final deliverRaw = json['deliver'];
    List<String> deliverList;
    if (deliverRaw is List) {
      deliverList = deliverRaw.map((e) => e.toString()).toList(growable: false);
    } else if (deliverRaw != null) {
      deliverList = [deliverRaw.toString()];
    } else {
      deliverList = const ['local'];
    }

    return HermesCronJob(
      id: json['id'].toString(),
      name: (json['name']?.toString().trim().isNotEmpty == true) ? json['name'].toString() : '未命名任务',
      schedule: scheduleText,
      prompt: (json['prompt'] ?? '').toString(),
      state: state,
      enabled: enabled,
      nextRunAt: json['next_run_at']?.toString(),
      lastRunAt: json['last_run_at']?.toString(),
      lastStatus: json['last_status']?.toString(),
      lastError: json['last_error']?.toString(),
      deliver: deliverList,
    );
  }

  String get stateLabel {
    switch (state) {
      case 'paused':
        return '已暂停';
      case 'completed':
        return '已完成';
      default:
        return '运行中';
    }
  }

  String get deliverLabel {
    const labels = {
      'local': '本地',
      'origin': '来源端',
      'telegram': 'Telegram',
      'discord': 'Discord',
      'slack': 'Slack',
      'whatsapp': 'WhatsApp',
      'signal': 'Signal',
      'matrix': 'Matrix',
      'mattermost': 'Mattermost',
      'email': '邮件',
      'webhook': 'Webhook',
      'sms': '短信',
      'homeassistant': 'Home Assistant',
      'dingtalk': '钉钉',
      'feishu': '飞书',
      'wecom': '企业微信',
    };
    if (deliver.isEmpty) return '本地';
    return deliver.map((d) => labels[d] ?? d).join('、');
  }
}

class JobsAdminApi {
  JobsAdminApi(this._dio);

  factory JobsAdminApi.fromClient(ApiClient client) => JobsAdminApi(client.dio);

  final Dio _dio;

  Future<List<HermesCronJob>> listJobs({bool includeDisabled = true}) async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/v1/admin/jobs',
        queryParameters: {'include_disabled': includeDisabled},
      );
      final jobs = response.data?['jobs'];
      if (jobs is! List) return const [];
      return jobs
          .whereType<Map>()
          .map((e) => HermesCronJob.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '加载计划任务失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> createJob({
    required String schedule,
    String name = '',
    String prompt = '',
    String deliver = 'local',
  }) async {
    try {
      await _dio.post<void>(
        '/v1/admin/jobs',
        data: {
          'name': name,
          'schedule': schedule,
          'prompt': prompt,
          'deliver': deliver,
        },
      );
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ??
            e.response?.data?['error'] as String? ??
            e.message ??
            '创建任务失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> deleteJob(String id) async {
    try {
      await _dio.delete<void>('/v1/admin/jobs/$id');
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ?? e.message ?? '删除任务失败',
        statusCode: e.response?.statusCode,
      );
    }
  }

  Future<void> jobAction(String id, String action) async {
    try {
      await _dio.post<void>('/v1/admin/jobs/$id/$action');
    } on DioException catch (e) {
      throw ApiException(
        e.response?.data?['message'] as String? ??
            e.response?.data?['error'] as String? ??
            e.message ??
            '操作失败',
        statusCode: e.response?.statusCode,
      );
    }
  }
}
