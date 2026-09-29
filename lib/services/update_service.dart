import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

class UpdateFailure implements Exception {
  UpdateFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class ReleaseAsset {
  const ReleaseAsset({required this.name, required this.url, required this.size});

  final String name;
  final String url;
  final int size;
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.pageUrl,
    required this.assets,
    required this.publishedAt,
  });

  final String tag;
  final String name;
  final String notes;
  final String pageUrl;
  final List<ReleaseAsset> assets;
  final DateTime? publishedAt;

  String get version => tag.replaceFirst(RegExp(r'^v'), '');

  static final _abiInName = RegExp(r'(arm64-v8a|armeabi-v7a|x86_64|x86)');

  ReleaseAsset? apkFor(List<String> abis) {
    final apks =
        assets.where((a) => a.name.toLowerCase().endsWith('.apk')).toList(growable: false);
    if (apks.isEmpty) return null;
    for (final abi in abis) {
      for (final asset in apks) {
        if (asset.name.contains(abi)) return asset;
      }
    }
    for (final asset in apks) {
      if (!_abiInName.hasMatch(asset.name)) return asset;
    }
    return apks.first;
  }

  ReleaseAsset? checksumFor(ReleaseAsset apk) {
    final wanted = '${apk.name}.sha256';
    for (final asset in assets) {
      if (asset.name == wanted) return asset;
    }
    return null;
  }

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final assets = <ReleaseAsset>[];
    for (final raw in (json['assets'] as List?) ?? const []) {
      final map = raw as Map<String, dynamic>;
      final url = map['browser_download_url'] as String?;
      final name = map['name'] as String?;
      if (url == null || name == null) continue;
      assets.add(ReleaseAsset(
        name: name,
        url: url,
        size: (map['size'] as num?)?.toInt() ?? 0,
      ));
    }
    return ReleaseInfo(
      tag: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      notes: json['body'] as String? ?? '',
      pageUrl: json['html_url'] as String? ?? '',
      assets: assets,
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? ''),
    );
  }
}

int compareVersions(String left, String right) {
  List<int> parts(String value) {
    final core = value.split(RegExp(r'[-+]')).first;
    final numbers = core.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return numbers;
  }

  final a = parts(left);
  final b = parts(right);
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i].compareTo(b[i]);
  }
  return 0;
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  void close() => _client.close();

  Future<ReleaseInfo?> latest({required String repoUrl, required String currentVersion}) async {
    final slug = _slug(repoUrl);
    if (slug == null) return null;
    try {
      final response = await _client.get(
        Uri.parse('https://api.github.com/repos/$slug/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) return null;
      if (data['draft'] == true || data['prerelease'] == true) return null;
      final release = ReleaseInfo.fromJson(data);
      if (release.version.isEmpty) return null;
      return compareVersions(release.version, currentVersion) > 0 ? release : null;
    } catch (_) {
      return null;
    }
  }

  Future<File> download(
    ReleaseAsset apk, {
    ReleaseAsset? checksum,
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/${apk.name}');
    if (await file.exists()) {
      await file.delete();
    }

    http.StreamedResponse response;
    try {
      response = await _client
          .send(http.Request('GET', Uri.parse(apk.url)))
          .timeout(const Duration(seconds: 30));
    } catch (_) {
      throw UpdateFailure('Не удалось начать скачивание, проверьте связь');
    }
    if (response.statusCode != 200) {
      throw UpdateFailure('Сервер отдал ошибку ${response.statusCode}');
    }

    final total = response.contentLength ?? apk.size;
    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0).toDouble());
      }
    } catch (_) {
      await sink.close();
      await _drop(file);
      throw UpdateFailure('Скачивание оборвалось');
    }
    await sink.close();

    if (checksum != null) {
      final expected = await _expected(checksum);
      if (expected != null) {
        final actual = (await sha256.bind(file.openRead()).first).toString().toLowerCase();
        if (actual != expected) {
          await _drop(file);
          throw UpdateFailure('Контрольная сумма не совпала, файл повреждён');
        }
      }
    }

    return file;
  }

  Future<void> install(File file) async {
    final result = await OpenFilex.open(
      file.path,
      type: 'application/vnd.android.package-archive',
    );
    switch (result.type) {
      case ResultType.done:
        return;
      case ResultType.noAppToOpen:
        throw UpdateFailure('Не нашлось установщика пакетов');
      case ResultType.permissionDenied:
        throw UpdateFailure('Разрешите установку приложений из этого источника и повторите');
      case ResultType.fileNotFound:
        throw UpdateFailure('Скачанный файл пропал, попробуйте заново');
      case ResultType.error:
        throw UpdateFailure('Не удалось открыть установщик');
    }
  }

  Future<String?> _expected(ReleaseAsset asset) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(asset.url)).timeout(const Duration(seconds: 20));
    } catch (_) {
      throw UpdateFailure('Не удалось получить контрольную сумму');
    }
    if (response.statusCode != 200) {
      throw UpdateFailure('Не удалось получить контрольную сумму');
    }
    final token = utf8.decode(response.bodyBytes).trim().split(RegExp(r'\s+')).first.toLowerCase();
    if (token.length != 64 || !RegExp(r'^[0-9a-f]+$').hasMatch(token)) return null;
    return token;
  }

  Future<void> _drop(File file) async {
    try {
      await file.delete();
    } catch (_) {}
  }

  String? _slug(String repoUrl) {
    final match = RegExp(r'github\.com/([^/]+/[^/]+)').firstMatch(repoUrl);
    if (match == null) return null;
    return match.group(1)!.replaceFirst(RegExp(r'\.git$'), '');
  }
}
