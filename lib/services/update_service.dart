import 'dart:convert';

import 'package:http/http.dart' as http;

class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.name,
    required this.notes,
    required this.pageUrl,
    required this.apkUrl,
    required this.publishedAt,
  });

  final String tag;
  final String name;
  final String notes;
  final String pageUrl;
  final String? apkUrl;
  final DateTime? publishedAt;

  String get version => tag.replaceFirst(RegExp(r'^v'), '');

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? apk;
    for (final asset in (json['assets'] as List?) ?? const []) {
      final map = asset as Map<String, dynamic>;
      final name = (map['name'] as String? ?? '').toLowerCase();
      if (name.endsWith('.apk')) {
        apk = map['browser_download_url'] as String?;
        break;
      }
    }
    return ReleaseInfo(
      tag: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? '',
      notes: json['body'] as String? ?? '',
      pageUrl: json['html_url'] as String? ?? '',
      apkUrl: apk,
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

  String? _slug(String repoUrl) {
    final match = RegExp(r'github\.com/([^/]+/[^/]+)').firstMatch(repoUrl);
    if (match == null) return null;
    return match.group(1)!.replaceFirst(RegExp(r'\.git$'), '');
  }
}
