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

/// Object specifying creation parameters for creating a [OhosWebStorageManager].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebStorageManagerCreationParams] for
/// more information.
@immutable
class OhosWebStorageManagerCreationParams
    extends PlatformWebStorageManagerCreationParams {
  /// Creates a new [OhosWebStorageManagerCreationParams] instance.
  const OhosWebStorageManagerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformWebStorageManagerCreationParams params,
  ) : super();

  /// Creates a [OhosWebStorageManagerCreationParams] instance based on [PlatformWebStorageManagerCreationParams].
  factory OhosWebStorageManagerCreationParams.fromPlatformWebStorageManagerCreationParams(
      PlatformWebStorageManagerCreationParams params) {
    return OhosWebStorageManagerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformWebStorageManager}
class OhosWebStorageManager extends PlatformWebStorageManager
    with ChannelController {
  /// Creates a new [OhosWebStorageManager].
  OhosWebStorageManager(PlatformWebStorageManagerCreationParams params)
      : super.implementation(
          params is OhosWebStorageManagerCreationParams
              ? params
              : OhosWebStorageManagerCreationParams
                  .fromPlatformWebStorageManagerCreationParams(params),
        ) {
    channel = const MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_webstoragemanager');
    handler = handleMethod;
    initMethodCallHandler();
  }

  static OhosWebStorageManager? _instance;

  ///Gets the WebStorage manager shared instance.
  static OhosWebStorageManager instance() {
    return (_instance != null) ? _instance! : _init();
  }

  static OhosWebStorageManager _init() {
    _instance = OhosWebStorageManager(OhosWebStorageManagerCreationParams(
        const PlatformWebStorageManagerCreationParams()));
    return _instance!;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {}

  @override
  Future<List<WebStorageOrigin>> getOrigins() async {
    List<WebStorageOrigin> originsList = [];

    Map<String, dynamic> args = <String, dynamic>{};
    List<Map<dynamic, dynamic>> origins =
        (await channel?.invokeMethod<List>('getOrigins', args))
                ?.cast<Map<dynamic, dynamic>>() ??
            [];

    for (var origin in origins) {
      originsList.add(WebStorageOrigin(
          origin: origin["origin"],
          quota: origin["quota"],
          usage: origin["usage"]));
    }

    return originsList;
  }

  @override
  Future<void> deleteAllData() async {
    Map<String, dynamic> args = <String, dynamic>{};
    await channel?.invokeMethod('deleteAllData', args);
  }

  @override
  Future<void> deleteOrigin({required String origin}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("origin", () => origin);
    await channel?.invokeMethod('deleteOrigin', args);
  }

  @override
  Future<int> getQuotaForOrigin({required String origin}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("origin", () => origin);
    return await channel?.invokeMethod<int>('getQuotaForOrigin', args) ?? 0;
  }

  @override
  Future<int> getUsageForOrigin({required String origin}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("origin", () => origin);
    return await channel?.invokeMethod<int>('getUsageForOrigin', args) ?? 0;
  }

  @override
  void dispose() {
    // empty
  }
}

extension InternalWebStorageManager on OhosWebStorageManager {
  get handleMethod => _handleMethod;
}
