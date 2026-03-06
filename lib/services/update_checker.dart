import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String installerUrl;
  final List<String> notes;

  UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.installerUrl,
    required this.notes,
  });

  bool get hasUpdate => _compareVersions(latestVersion, currentVersion) > 0;

  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map(int.parse).toList();
    final bParts = b.split('.').map(int.parse).toList();

    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;

      if (av > bv) return 1;
      if (av < bv) return -1;
    }

    return 0;
  }
}

class UpdateChecker {
  final Uri endpoint;

  const UpdateChecker(this.endpoint);

  Future<UpdateInfo?> check() async {
    final package = await PackageInfo.fromPlatform();

    final response = await http.get(endpoint);

    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body);

    return UpdateInfo(
      currentVersion: package.version,
      latestVersion: data['latestVersion'],
      installerUrl: data['installerUrl'],
      notes: (data['notes'] as List).map((e) => e.toString()).toList(),
    );
  }
}