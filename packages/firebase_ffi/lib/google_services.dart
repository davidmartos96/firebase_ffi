// SPDX-FileCopyrightText: 2026 Joel Winarske
// SPDX-License-Identifier: Apache-2.0

/// Reads the `google-services.json` the Firebase console generates, so the
/// project a build talks to is a deployed file rather than constants compiled
/// into the app.
///
/// This is the Android config file verbatim — the same one FlutterFire consumes
/// — which matters because the Linux desktop SDK is configured from the Android
/// options (there is no Linux-specific config file, and the console does not
/// emit one).
library;

import 'dart:convert';
import 'dart:io';

/// What the console writes for a project. Only the app id, the key and the
/// project id are always there; the rest depend on which products the project
/// has, so they are nullable.
class GoogleServicesConfig {
  const GoogleServicesConfig({
    required this.appId,
    required this.apiKey,
    required this.projectId,
    this.databaseUrl,
    this.storageBucket,
    this.messagingSenderId,
  });

  final String appId;
  final String apiKey;
  final String projectId;

  /// Null when the project has no Realtime Database. The console writes
  /// `firebase_url` only once one exists, and a project using Firestore or
  /// Auth alone never gets one — so its absence is ordinary, not an error.
  /// `initDatabase` is where it has to be present.
  final String? databaseUrl;
  final String? storageBucket;

  /// The project number, which is what Firebase calls the messaging sender id.
  /// Unused by the C++ SDK on desktop, but `FirebaseOptions` requires it, and
  /// the console writes it — so it is carried rather than invented.
  final String? messagingSenderId;

  /// Where to look when no path is given: the environment variable first, then
  /// the working directory, which for a deployed bundle is the bundle root.
  static const envVar = 'GOOGLE_SERVICES_JSON';
  static const defaultFileName = 'google-services.json';

  static String resolvePath([String? path]) =>
      path ?? Platform.environment[envVar] ?? defaultFileName;

  /// Parses [path], or the default location.
  ///
  /// Throws [FormatException] naming the field that was missing, rather than
  /// letting a partial config reach the SDK and fail as an opaque init error.
  static GoogleServicesConfig load([String? path]) {
    final file = File(resolvePath(path));
    if (!file.existsSync()) {
      throw FileSystemException('no google-services.json', file.path);
    }
    return parse(file.readAsStringSync(), source: file.path);
  }

  static GoogleServicesConfig parse(String text, {String source = '<memory>'}) {
    final Object? decoded = json.decode(text);
    if (decoded is! Map<String, Object?>) {
      throw FormatException('$source: expected a JSON object');
    }

    Map<String, Object?> obj(Map<String, Object?> from, String key) {
      final v = from[key];
      if (v is! Map<String, Object?>) {
        throw FormatException('$source: missing object "$key"');
      }
      return v;
    }

    String str(Map<String, Object?> from, String key) {
      final v = from[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('$source: missing string "$key"');
      }
      return v;
    }

    final info = obj(decoded, 'project_info');

    // One project can register several apps. Without a package name to match,
    // a single client is unambiguous; more than one is not, so say so instead
    // of silently taking the first.
    final clients = decoded['client'];
    if (clients is! List || clients.isEmpty) {
      throw FormatException('$source: no "client" entries');
    }
    if (clients.length > 1) {
      throw FormatException(
        '$source: ${clients.length} clients registered; this loader needs '
        'exactly one to pick without ambiguity',
      );
    }
    final client = clients.first;
    if (client is! Map<String, Object?>) {
      throw FormatException('$source: malformed "client" entry');
    }

    final keys = client['api_key'];
    if (keys is! List || keys.isEmpty || keys.first is! Map<String, Object?>) {
      throw FormatException('$source: no "api_key" for the client');
    }

    return GoogleServicesConfig(
      appId: str(obj(client, 'client_info'), 'mobilesdk_app_id'),
      apiKey: str(keys.first as Map<String, Object?>, 'current_key'),
      projectId: str(info, 'project_id'),
      // Absent for a project with no Realtime Database, which is most of
      // them. Failing here would stop an app that never asks for one.
      databaseUrl: switch (info['firebase_url']) {
        final String v when v.isNotEmpty => v,
        _ => null,
      },
      storageBucket: info['storage_bucket'] as String?,
      messagingSenderId: info['project_number'] as String?,
    );
  }

  @override
  String toString() =>
      'GoogleServicesConfig($projectId, ${databaseUrl ?? 'no database'})';
}
