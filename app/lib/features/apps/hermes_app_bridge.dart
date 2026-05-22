import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:share_plus/share_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/chat/chat_image_compress.dart';
import '../../core/network/api_client.dart';
import '../../core/ui/app_message.dart';
import 'hermes_file_io.dart';

/// WebView ↔ 原生能力桥，对应 Gateway `hermes-app-host.js`。
class HermesAppBridge {
  HermesAppBridge({
    required WebViewController controller,
    required ApiClient apiClient,
    required bool Function() mounted,
  })  : _controller = controller,
        _apiClient = apiClient,
        _mounted = mounted;

  final WebViewController _controller;
  final ApiClient _apiClient;
  final bool Function() _mounted;

  static const _maxUploadBytes = 8 * 1024 * 1024;
  static const _maxPickBytes = 50 * 1024 * 1024;

  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _audioRecordingPath;

  void attach() {
    _controller.addJavaScriptChannel(
      'HermesAppBridge',
      onMessageReceived: (message) {
        unawaited(_onMessage(message.message));
      },
    );
  }

  Future<void> notifyNativeReady() async {
    if (!_mounted()) return;
    final payload = jsonEncode({
      'capabilities': _capabilities(),
      'saveDestinations': _saveDestinations(),
    });
    await _controller.runJavaScript('window.__hermesAppNativeReady($payload)');
  }

  Map<String, bool> _capabilities() => const {
        'pickImage': true,
        'pickFile': true,
        'pickVideo': true,
        'uploadBlob': true,
        'compressImage': true,
        'saveFile': true,
        'shareFile': true,
        'share': true,
        'toast': true,
        'clipboard': true,
        'recordAudio': true,
      };

  Map<String, String> _saveDestinations() => const {
        'image': 'gallery',
        'video': 'gallery',
        'audio': 'downloads',
        'document': 'downloads',
        'archive': 'downloads',
        'text': 'downloads',
        'other': 'downloads',
      };

  Future<void> dispose() async {
    if (await _audioRecorder.isRecording()) {
      await _audioRecorder.stop();
    }
    await _audioRecorder.dispose();
    if (_audioRecordingPath != null) {
      final f = File(_audioRecordingPath!);
      if (await f.exists()) await f.delete();
    }
    _audioRecordingPath = null;
  }

  Future<void> _onMessage(String raw) async {
    String id = '';
    try {
      final msg = jsonDecode(raw) as Map<String, dynamic>;
      id = msg['id']?.toString() ?? '';
      final method = msg['method']?.toString() ?? '';
      final params = (msg['params'] as Map?)?.cast<String, dynamic>() ?? {};
      if (id.isEmpty || method.isEmpty) return;
      final result = await _dispatch(method, params);
      await _deliver(id, result);
    } catch (e) {
      if (id.isNotEmpty) {
        await _deliver(id, _err('INTERNAL', e.toString()));
      }
    }
  }

  Future<Map<String, dynamic>> _dispatch(String method, Map<String, dynamic> params) {
    switch (method) {
      case 'pickImage':
        return _pickImage(params);
      case 'pickFile':
        return _pickFile(params);
      case 'pickVideo':
        return _pickVideo(params);
      case 'uploadBlob':
        return _uploadBlob(params);
      case 'compressImage':
        return _compressImage(params);
      case 'saveFile':
        return _saveFile(params);
      case 'shareFile':
        return _shareFile(params);
      case 'share':
        return _share(params);
      case 'toast':
        return _toast(params);
      case 'clipboard.readText':
        return _clipboardReadText();
      case 'clipboard.writeText':
        return _clipboardWriteText(params);
      case 'recordAudio.start':
        return _recordAudioStart(params);
      case 'recordAudio.stop':
        return _recordAudioStop(params);
      default:
        return Future.value(_err('UNKNOWN_METHOD', '不支持的方法: $method'));
    }
  }

  Future<void> _deliver(String id, Map<String, dynamic> payload) async {
    if (!_mounted()) return;
    final encoded = jsonEncode(payload);
    await _controller.runJavaScript(
      'window.__hermesAppDeliver(${jsonEncode(id)}, $encoded)',
    );
  }

  Map<String, dynamic> _err(String code, String message) => {
        'ok': false,
        'code': code,
        'message': message,
      };

  Map<String, dynamic> _ok(Map<String, dynamic> data) => {'ok': true, ...data};

  ImageSource _imageSource(Map<String, dynamic> params) {
    final source = params['source']?.toString() ?? 'gallery';
    return source == 'camera' ? ImageSource.camera : ImageSource.gallery;
  }

  Future<Map<String, dynamic>> _pickImage(Map<String, dynamic> params) async {
    if (_imageSource(params) == ImageSource.camera) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return _err('PERMISSION_DENIED', '需要相机权限');
    }
    final picked = await _imagePicker.pickImage(source: _imageSource(params));
    if (picked == null) return _err('CANCELLED', '用户取消');
    var bytes = await picked.readAsBytes();
    if (bytes.length > _maxPickBytes) return _err('TOO_LARGE', '图片过大（最大 50MB）');

    final compress = params['compress'] != false;
    if (compress) {
      try {
        final out = await ChatImageCompressor.compress(
          input: bytes,
          filePath: picked.path,
          filename: picked.name.isNotEmpty ? picked.name : 'image.jpg',
        );
        bytes = out.bytes;
      } on Object {
        /* 压缩失败仍返回原图 */
      }
    }

    final upload = params['upload'] == true;
    return _fileResult(
      bytes: bytes,
      filename: picked.name.isNotEmpty ? picked.name : 'image.jpg',
      mimeType: HermesMime.guess(picked.name, fallback: 'image/jpeg'),
      upload: upload,
    );
  }

  Future<Map<String, dynamic>> _pickFile(Map<String, dynamic> params) async {
    List<String>? allowedExtensions;
    final rawExts = params['allowedExtensions'];
    if (rawExts is List && rawExts.isNotEmpty) {
      allowedExtensions = rawExts.map((e) => e.toString().replaceAll('.', '').toLowerCase()).toList();
    }
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: allowedExtensions != null ? FileType.custom : FileType.any,
      allowedExtensions: allowedExtensions,
    );
    if (result == null || result.files.isEmpty) return _err('CANCELLED', '用户取消');
    final f = result.files.first;
    final bytes = f.bytes;
    if (bytes == null) return _err('UNAVAILABLE', '无法读取文件');
    final maxBytes = params['maxBytes'] is num
        ? (params['maxBytes'] as num).toInt()
        : _maxPickBytes;
    if (bytes.length > maxBytes) {
      return _err('TOO_LARGE', '文件过大');
    }
    final upload = params['upload'] == true;
    return _fileResult(
      bytes: bytes,
      filename: f.name,
      mimeType: HermesMime.guess(f.name),
      upload: upload,
    );
  }

  Future<Map<String, dynamic>> _pickVideo(Map<String, dynamic> params) async {
    if (_imageSource(params) == ImageSource.camera) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return _err('PERMISSION_DENIED', '需要相机权限');
    }
    final picked = await _imagePicker.pickVideo(
      source: _imageSource(params),
      maxDuration: params['maxDurationSec'] is num
          ? Duration(seconds: (params['maxDurationSec'] as num).toInt())
          : null,
    );
    if (picked == null) return _err('CANCELLED', '用户取消');
    final bytes = await picked.readAsBytes();
    if (bytes.length > _maxPickBytes) return _err('TOO_LARGE', '视频过大（最大 50MB）');
    final upload = params['upload'] == true;
    return _fileResult(
      bytes: bytes,
      filename: picked.name.isNotEmpty ? picked.name : 'video.mp4',
      mimeType: HermesMime.guess(picked.name, fallback: 'video/mp4'),
      upload: upload,
    );
  }

  Future<Map<String, dynamic>> _uploadBlob(Map<String, dynamic> params) async {
    final b64 = params['base64']?.toString() ?? '';
    if (b64.isEmpty) return _err('INVALID', '缺少 base64');
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return _err('INVALID', 'base64 无效');
    }
    if (bytes.length > _maxUploadBytes) return _err('TOO_LARGE', '文件过大（最大 8MB）');
    final filename = params['filename']?.toString() ?? 'upload.bin';
    final mimeType = params['mimeType']?.toString() ?? HermesMime.guess(filename);
    return _fileResult(bytes: bytes, filename: filename, mimeType: mimeType, upload: true);
  }

  Future<Map<String, dynamic>> _compressImage(Map<String, dynamic> params) async {
    final b64 = params['base64']?.toString() ?? '';
    if (b64.isEmpty) return _err('INVALID', '缺少 base64');
    Uint8List bytes;
    try {
      bytes = base64Decode(b64);
    } catch (_) {
      return _err('INVALID', 'base64 无效');
    }
    try {
      final out = await ChatImageCompressor.compress(
        input: bytes,
        filename: params['filename']?.toString() ?? 'image.jpg',
      );
      return _ok({
        'base64': base64Encode(out.bytes),
        'mimeType': out.mimeType,
        'filename': out.filename,
        'size': out.bytes.length,
        'compressed': out.compressed,
        'originalSize': out.originalBytes,
      });
    } on ChatImageTooLargeException catch (e) {
      return _err('TOO_LARGE', e.message);
    }
  }

  Future<Map<String, dynamic>> _saveFile(Map<String, dynamic> params) async {
    final filename = params['filename']?.toString() ?? 'download.bin';
    final resolved = await _resolveFileBytes(params);
    if (resolved case ('err', final err)) return err;
    final (_, bytes) = resolved;
    final mimeType = params['mimeType']?.toString() ?? HermesMime.guess(filename);
    final usePicker = params['picker'] == true || params['destination']?.toString() == 'picker';

    try {
      final saved = await HermesFileIo.saveBytes(
        bytes: bytes as Uint8List,
        filename: filename,
        mimeType: mimeType,
        usePicker: usePicker,
        onSuccess: _mounted() ? (msg) => AppMessage.success(msg) : null,
      );
      return _ok(saved.toJson());
    } on HermesFileIoException catch (e) {
      return _err(e.code, e.message);
    } catch (e) {
      return _err('SAVE_FAILED', e.toString());
    }
  }

  Future<Map<String, dynamic>> _shareFile(Map<String, dynamic> params) async {
    final filename = params['filename']?.toString() ?? 'share.bin';
    final resolved = await _resolveFileBytes(params);
    if (resolved case ('err', final err)) return err;
    final (_, bytes) = resolved;
    final mimeType = params['mimeType']?.toString() ?? HermesMime.guess(filename);
    final title = params['title']?.toString() ?? '';

    try {
      await HermesFileIo.shareBytes(
        bytes: bytes as Uint8List,
        filename: filename,
        mimeType: mimeType,
        title: title,
      );
      return _ok({
        'filename': HermesFileIo.safeFilename(filename),
        'size': (bytes).length,
        'mimeType': mimeType,
        'category': HermesMime.category(mimeType, filename).name,
        'shared': true,
      });
    } on HermesFileIoException catch (e) {
      return _err(e.code, e.message);
    } catch (e) {
      return _err('SHARE_FAILED', e.toString());
    }
  }

  Future<(String, dynamic)> _resolveFileBytes(Map<String, dynamic> params) async {
    final b64 = params['base64']?.toString();
    if (b64 != null && b64.isNotEmpty) {
      try {
        return ('ok', base64Decode(b64));
      } catch (_) {
        return ('err', _err('INVALID', 'base64 无效'));
      }
    }
    final url = params['url']?.toString() ?? '';
    if (url.isEmpty) return ('err', _err('INVALID', '需要 base64 或 url'));
    try {
      final dio = Dio();
      final resp = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes, headers: _authHeaders()),
      );
      return ('ok', Uint8List.fromList(resp.data ?? const []));
    } catch (e) {
      return ('err', _err('DOWNLOAD_FAILED', e.toString()));
    }
  }

  Future<Map<String, dynamic>> _share(Map<String, dynamic> params) async {
    final text = params['text']?.toString() ?? '';
    final url = params['url']?.toString() ?? '';
    final title = params['title']?.toString() ?? '';
    final body = [if (title.isNotEmpty) title, if (text.isNotEmpty) text, if (url.isNotEmpty) url]
        .join('\n')
        .trim();
    if (body.isEmpty) return _err('INVALID', '无可分享内容');
    await SharePlus.instance.share(ShareParams(text: body, subject: title.isNotEmpty ? title : null));
    return _ok({'shared': true});
  }

  Future<Map<String, dynamic>> _toast(Map<String, dynamic> params) async {
    final message = params['message']?.toString() ?? '';
    if (message.isNotEmpty) AppMessage.info(message);
    return _ok({'shown': true});
  }

  Future<Map<String, dynamic>> _clipboardReadText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return _ok({'text': data?.text ?? ''});
  }

  Future<Map<String, dynamic>> _clipboardWriteText(Map<String, dynamic> params) async {
    final text = params['text']?.toString() ?? '';
    await Clipboard.setData(ClipboardData(text: text));
    return _ok({'written': true});
  }

  Future<Map<String, dynamic>> _recordAudioStart(Map<String, dynamic> params) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return _err('PERMISSION_DENIED', '需要麦克风权限');
    if (await _audioRecorder.isRecording()) {
      return _err('BUSY', '已在录音中');
    }
    final dir = await getTemporaryDirectory();
    _audioRecordingPath = '${dir.path}/hermes-rec-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: _audioRecordingPath!,
    );
    return _ok({'recording': true, 'path': _audioRecordingPath});
  }

  Future<Map<String, dynamic>> _recordAudioStop(Map<String, dynamic> params) async {
    if (!await _audioRecorder.isRecording()) {
      return _err('NOT_RECORDING', '当前未在录音');
    }
    final path = await _audioRecorder.stop();
    final filePath = path ?? _audioRecordingPath;
    if (filePath == null) return _err('UNAVAILABLE', '录音文件不存在');
    final file = File(filePath);
    if (!await file.exists()) return _err('UNAVAILABLE', '录音文件不存在');
    final bytes = await file.readAsBytes();
    final upload = params['upload'] == true;
    final result = await _fileResult(
      bytes: bytes,
      filename: 'recording.m4a',
      mimeType: 'audio/mp4',
      upload: upload,
    );
    _audioRecordingPath = null;
    return result;
  }

  Future<Map<String, dynamic>> _fileResult({
    required Uint8List bytes,
    required String filename,
    required String mimeType,
    required bool upload,
  }) async {
    final data = <String, dynamic>{
      'base64': base64Encode(bytes),
      'filename': filename,
      'mimeType': mimeType,
      'size': bytes.length,
      'category': HermesMime.category(mimeType, filename).name,
    };
    if (upload) {
      if (bytes.length > _maxUploadBytes) {
        return _err('TOO_LARGE', '文件过大（最大 8MB）');
      }
      final up = await _apiClient.uploadFile(
        bytes: bytes,
        filename: filename,
        mimeType: mimeType,
      );
      if (up.url != null && up.url!.isNotEmpty) data['url'] = up.url;
      data['uploadId'] = up.id;
      data['downloadPath'] = up.downloadPath;
    }
    return _ok(data);
  }

  Map<String, String> _authHeaders() {
    final auth = _apiClient.dio.options.headers['Authorization']?.toString();
    if (auth == null || auth.isEmpty) return const {};
    return {'Authorization': auth};
  }
}
