/*
* Copyright (c) 2024 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

import '../in_app_webview/in_app_webview_controller.dart';

/// Object specifying creation parameters for creating a [OhosWebViewEnvironment].
@immutable
class OhosWebViewEnvironmentCreationParams
    extends PlatformWebViewEnvironmentCreationParams {
  const OhosWebViewEnvironmentCreationParams({super.settings});

  factory OhosWebViewEnvironmentCreationParams.fromPlatformWebViewEnvironmentCreationParams(
      PlatformWebViewEnvironmentCreationParams params) {
    return OhosWebViewEnvironmentCreationParams(settings: params.settings);
  }
}

/// OHOS implementation of [PlatformWebViewEnvironment].
///
/// ArkWeb is system-managed, so this provides API-compatible helpers without a
/// separate native environment object.
class OhosWebViewEnvironment extends PlatformWebViewEnvironment {
  @override
  final String id = IdGenerator.generate();

  OhosWebViewEnvironment(PlatformWebViewEnvironmentCreationParams params)
      : super.implementation(params is OhosWebViewEnvironmentCreationParams
            ? params
            : OhosWebViewEnvironmentCreationParams
                .fromPlatformWebViewEnvironmentCreationParams(params));

  static final OhosWebViewEnvironment _staticValue =
      OhosWebViewEnvironment(OhosWebViewEnvironmentCreationParams());

  factory OhosWebViewEnvironment.static() {
    return _staticValue;
  }

  @override
  Future<OhosWebViewEnvironment> create(
      {WebViewEnvironmentSettings? settings}) async {
    return OhosWebViewEnvironment(
        OhosWebViewEnvironmentCreationParams(settings: settings));
  }

  @override
  Future<String?> getAvailableVersion({String? browserExecutableFolder}) async {
    final userAgent =
        await OhosInAppWebViewController.static().getDefaultUserAgent();
    return _parseVersionFromUserAgent(userAgent);
  }

  @override
  Future<int?> compareBrowserVersions(
      {required String version1, required String version2}) {
    return Future<int?>.value(_compareBrowserVersions(version1, version2));
  }

  @override
  Future<void> dispose() async {}

  static String? _parseVersionFromUserAgent(String userAgent) {
    final chromeMatch =
        RegExp(r'Chrome/([\d.]+)').firstMatch(userAgent);
    if (chromeMatch != null && chromeMatch.groupCount >= 1) {
      final version = chromeMatch.group(1);
      if (version != null && version.isNotEmpty) {
        return version;
      }
    }

    final arkMatch = RegExp(r'ArkWeb/([\d.]+)').firstMatch(userAgent);
    if (arkMatch != null && arkMatch.groupCount >= 1) {
      final version = arkMatch.group(1);
      if (version != null && version.isNotEmpty) {
        return version;
      }
    }

    return null;
  }

  static int? _compareBrowserVersions(String version1, String version2) {
    final parts1 = _parseVersionParts(version1);
    final parts2 = _parseVersionParts(version2);
    if (parts1 == null || parts2 == null) {
      return null;
    }

    final length =
        parts1.length > parts2.length ? parts1.length : parts2.length;
    for (var i = 0; i < length; i++) {
      final left = i < parts1.length ? parts1[i] : 0;
      final right = i < parts2.length ? parts2[i] : 0;
      if (left < right) {
        return -1;
      }
      if (left > right) {
        return 1;
      }
    }
    return 0;
  }

  static List<int>? _parseVersionParts(String version) {
    if (version.isEmpty) {
      return null;
    }

    final parts = <int>[];
    for (final segment in version.split('.')) {
      final value = int.tryParse(segment);
      if (value == null) {
        return null;
      }
      parts.add(value);
    }
    return parts;
  }
}
