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

/// Object specifying creation parameters for creating a [OhosTracingController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformTracingControllerCreationParams] for
/// more information.
@immutable
class OhosTracingControllerCreationParams
    extends PlatformTracingControllerCreationParams {
  /// Creates a new [OhosTracingControllerCreationParams] instance.
  const OhosTracingControllerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformTracingControllerCreationParams params,
  ) : super();

  /// Creates a [OhosTracingControllerCreationParams] instance based on [PlatformTracingControllerCreationParams].
  factory OhosTracingControllerCreationParams.fromPlatformTracingControllerCreationParams(
      PlatformTracingControllerCreationParams params) {
    return OhosTracingControllerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformTracingController}
class OhosTracingController extends PlatformTracingController
    with ChannelController {
  /// Creates a new [OhosTracingController].
  OhosTracingController(PlatformTracingControllerCreationParams params)
      : super.implementation(
          params is OhosTracingControllerCreationParams
              ? params
              : OhosTracingControllerCreationParams
                  .fromPlatformTracingControllerCreationParams(params),
        ) {
    channel = const MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_tracingcontroller');
    handler = handleMethod;
    initMethodCallHandler();
  }

  static OhosTracingController? _instance;

  ///Gets the [OhosTracingController] shared instance.
  static OhosTracingController instance() {
    return (_instance != null) ? _instance! : _init();
  }

  static OhosTracingController _init() {
    _instance = OhosTracingController(OhosTracingControllerCreationParams(
        const PlatformTracingControllerCreationParams()));
    return _instance!;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {}

  @override
  Future<void> start({required TracingSettings settings}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("settings", () => settings.toMap());
    await channel?.invokeMethod('start', args);
  }

  @override
  Future<bool> stop({String? filePath}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("filePath", () => filePath);
    return await channel?.invokeMethod<bool>('stop', args) ?? false;
  }

  @override
  Future<bool> isTracing() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('isTracing', args) ?? false;
  }

  @override
  void dispose() {
    // empty
  }
}

extension InternalTracingController on OhosTracingController {
  get handleMethod => _handleMethod;
}
