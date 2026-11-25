import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/release_notes.dart';

abstract final class ReleaseNotes {
  // Flutter replaces this asset's Markdown bytes with JSON during packaging.
  static Future<List<AppRelease>> load() => rootBundle
      .loadStructuredData<List<AppRelease>>('CHANGELOG.md', (source) async {
        final releases = jsonDecode(source) as List<dynamic>;
        return List.unmodifiable([
          for (final release in releases)
            AppRelease.fromJson(release as Map<String, dynamic>),
        ]);
      });
}
