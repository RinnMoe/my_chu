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

/// Object specifying creation parameters for creating a [OhosServiceWorkerController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformServiceWorkerControllerCreationParams] for
/// more information.
@immutable
class OhosServiceWorkerControllerCreationParams
    extends PlatformServiceWorkerControllerCreationParams {
  /// Creates a new [OhosServiceWorkerControllerCreationParams] instance.
  const OhosServiceWorkerControllerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformServiceWorkerControllerCreationParams params,
  ) : super();

  /// Creates a [OhosServiceWorkerControllerCreationParams] instance based on [PlatformServiceWorkerControllerCreationParams].
  factory OhosServiceWorkerControllerCreationParams.fromPlatformServiceWorkerControllerCreationParams(
      PlatformServiceWorkerControllerCreationParams params) {
    return OhosServiceWorkerControllerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformServiceWorkerController}
class OhosServiceWorkerController extends PlatformServiceWorkerController
    with ChannelController {
  /// Creates a new [OhosServiceWorkerController].
  OhosServiceWorkerController(
      PlatformServiceWorkerControllerCreationParams params)
      : super.implementation(
          params is OhosServiceWorkerControllerCreationParams
              ? params
              : OhosServiceWorkerControllerCreationParams
                  .fromPlatformServiceWorkerControllerCreationParams(params),
        ) {
    channel = const MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_serviceworkercontroller');
    handler = handleMethod;
    initMethodCallHandler();
  }

  factory OhosServiceWorkerController.static() {
    return instance();
  }

  static OhosServiceWorkerController? _instance;

  ///Gets the [OhosServiceWorkerController] shared instance.
  static OhosServiceWorkerController instance() {
    return (_instance != null) ? _instance! : _init();
  }

  static OhosServiceWorkerController _init() {
    _instance = OhosServiceWorkerController(
        OhosServiceWorkerControllerCreationParams(
            const PlatformServiceWorkerControllerCreationParams()));
    return _instance!;
  }

  ServiceWorkerClient? _serviceWorkerClient;

  @override
  ServiceWorkerClient? get serviceWorkerClient => _serviceWorkerClient;

  @override
  Future<void> setServiceWorkerClient(ServiceWorkerClient? value) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('isNull', () => value == null);
    await channel?.invokeMethod("setServiceWorkerClient", args);
    _serviceWorkerClient = value;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case "shouldInterceptRequest":
        if (serviceWorkerClient != null &&
            serviceWorkerClient!.shouldInterceptRequest != null) {
          Map<String, dynamic> arguments =
              call.arguments.cast<String, dynamic>();
          WebResourceRequest request = WebResourceRequest.fromMap(arguments)!;

          return (await serviceWorkerClient!.shouldInterceptRequest!(request))
              ?.toMap();
        }
        break;
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }

    return null;
  }

  @override
  Future<bool> getAllowContentAccess() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('getAllowContentAccess', args) ??
        false;
  }

  @override
  Future<bool> getAllowFileAccess() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('getAllowFileAccess', args) ??
        false;
  }

  @override
  Future<bool> getBlockNetworkLoads() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('getBlockNetworkLoads', args) ??
        false;
  }

  @override
  Future<CacheMode?> getCacheMode() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return CacheMode.fromNativeValue(
        await channel?.invokeMethod<int?>('getCacheMode', args));
  }

  @override
  Future<void> setAllowContentAccess(bool allow) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("allow", () => allow);
    await channel?.invokeMethod('setAllowContentAccess', args);
  }

  @override
  Future<void> setAllowFileAccess(bool allow) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("allow", () => allow);
    await channel?.invokeMethod('setAllowFileAccess', args);
  }

  @override
  Future<void> setBlockNetworkLoads(bool flag) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("flag", () => flag);
    await channel?.invokeMethod('setBlockNetworkLoads', args);
  }

  @override
  Future<void> setCacheMode(CacheMode mode) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("mode", () => mode.toNativeValue());
    await channel?.invokeMethod('setCacheMode', args);
  }

  @override
  void dispose() {
    // empty
  }
}

extension InternalServiceWorkerController on OhosServiceWorkerController {
  get handleMethod => _handleMethod;
}
