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

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// Object specifying creation parameters for creating a [OhosWebViewFeature].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebViewFeatureCreationParams] for
/// more information.
@immutable
class OhosWebViewFeatureCreationParams
    extends PlatformWebViewFeatureCreationParams {
  /// Creates a new [OhosWebViewFeatureCreationParams] instance.
  const OhosWebViewFeatureCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebViewFeatureCreationParams params,
  ) : super();

  /// Creates a [OhosWebViewFeatureCreationParams] instance based on [PlatformWebViewFeatureCreationParams].
  factory OhosWebViewFeatureCreationParams.fromPlatformWebViewFeatureCreationParams(
      PlatformWebViewFeatureCreationParams params) {
    return OhosWebViewFeatureCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformWebViewFeature}
class OhosWebViewFeature extends PlatformWebViewFeature
    with ChannelController {
  /// Creates a new [OhosWebViewFeature].
  OhosWebViewFeature(PlatformWebViewFeatureCreationParams params)
      : super.implementation(
          params is OhosWebViewFeatureCreationParams
              ? params
              : OhosWebViewFeatureCreationParams
                  .fromPlatformWebViewFeatureCreationParams(params),
        ) {
    channel = const MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_webviewfeature');
    handler = handleMethod;
    initMethodCallHandler();
  }

  factory OhosWebViewFeature.static() {
    return instance();
  }

  static OhosWebViewFeature? _instance;

  ///Gets the [OhosWebViewFeature] shared instance.
  static OhosWebViewFeature instance() {
    return (_instance != null) ? _instance! : _init();
  }

  static OhosWebViewFeature _init() {
    _instance = OhosWebViewFeature(OhosWebViewFeatureCreationParams(
        const PlatformWebViewFeatureCreationParams()));
    return _instance!;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {}

  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("feature", () => feature.toNativeValue());
    return await channel?.invokeMethod<bool>('isFeatureSupported', args) ??
        false;
  }

  @override
  Future<bool> isStartupFeatureSupported(WebViewFeature startupFeature) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("startupFeature", () => startupFeature.toNativeValue());
    return await channel?.invokeMethod<bool>(
            'isStartupFeatureSupported', args) ??
        false;
  }

  @override
  void dispose() {
    // empty
  }
}

extension InternalWebViewFeature on OhosWebViewFeature {
  get handleMethod => _handleMethod;
}
