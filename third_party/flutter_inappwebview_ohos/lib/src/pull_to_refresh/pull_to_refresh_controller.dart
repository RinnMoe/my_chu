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

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// Object specifying creation parameters for creating a [OhosPullToRefreshController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformPullToRefreshControllerCreationParams] for
/// more information.
class OhosPullToRefreshControllerCreationParams
    extends PlatformPullToRefreshControllerCreationParams {
  /// Creates a new [OhosPullToRefreshControllerCreationParams] instance.
  OhosPullToRefreshControllerCreationParams(
      {super.onRefresh, super.options, super.settings});

  /// Creates a [OhosPullToRefreshControllerCreationParams] instance based on [PlatformPullToRefreshControllerCreationParams].
  factory OhosPullToRefreshControllerCreationParams.fromPlatformPullToRefreshControllerCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformPullToRefreshControllerCreationParams params) {
    return OhosPullToRefreshControllerCreationParams(
        onRefresh: params.onRefresh,
        options: params.options,
        settings: params.settings);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformPullToRefreshController}
class OhosPullToRefreshController extends PlatformPullToRefreshController
    with ChannelController {
  /// Constructs a [OhosPullToRefreshController].
  OhosPullToRefreshController(
      PlatformPullToRefreshControllerCreationParams params)
      : super.implementation(
          params is OhosPullToRefreshControllerCreationParams
              ? params
              : OhosPullToRefreshControllerCreationParams
                  .fromPlatformPullToRefreshControllerCreationParams(params),
        );

  _debugLog(String method, dynamic args) {
    debugLog(
        className: this.runtimeType.toString(),
        debugLoggingSettings:
            PlatformPullToRefreshController.debugLoggingSettings,
        method: method,
        args: args);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    _debugLog(call.method, call.arguments);

    switch (call.method) {
      case "onRefresh":
        if (params.onRefresh != null) params.onRefresh!();
        break;
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
    return null;
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('enabled', () => enabled);
    await channel?.invokeMethod('setEnabled', args);
  }

  @override
  Future<bool> isEnabled() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('isEnabled', args) ?? false;
  }

  Future<void> _setRefreshing(bool refreshing) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('refreshing', () => refreshing);
    await channel?.invokeMethod('setRefreshing', args);
  }

  @override
  Future<void> beginRefreshing() async {
    return await _setRefreshing(true);
  }

  @override
  Future<void> endRefreshing() async {
    await _setRefreshing(false);
  }

  @override
  Future<bool> isRefreshing() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<bool>('isRefreshing', args) ?? false;
  }

  @override
  Future<void> setColor(Color color) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('color', () => color.toHex());
    await channel?.invokeMethod('setColor', args);
  }

  @override
  Future<void> setBackgroundColor(Color color) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('color', () => color.toHex());
    await channel?.invokeMethod('setBackgroundColor', args);
  }

  @override
  Future<void> setDistanceToTriggerSync(int distanceToTriggerSync) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('distanceToTriggerSync', () => distanceToTriggerSync);
    await channel?.invokeMethod('setDistanceToTriggerSync', args);
  }

  @override
  Future<void> setSlingshotDistance(int slingshotDistance) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('slingshotDistance', () => slingshotDistance);
    await channel?.invokeMethod('setSlingshotDistance', args);
  }

  @override
  Future<int> getDefaultSlingshotDistance() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<int>(
            'getDefaultSlingshotDistance', args) ??
        0;
  }

  @Deprecated("Use setIndicatorSize instead")
  @override
  Future<void> setSize(AndroidPullToRefreshSize size) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('size', () => size.toNativeValue());
    await channel?.invokeMethod('setSize', args);
  }

  @override
  Future<void> setIndicatorSize(PullToRefreshSize size) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('size', () => size.toNativeValue());
    await channel?.invokeMethod('setSize', args);
  }

  @override
  void dispose({bool isKeepAlive = false}) {
    if (disposed) {
      return;
    }
    disposeChannel(removeMethodCallHandler: !isKeepAlive);
  }
}

extension InternalPullToRefreshController on OhosPullToRefreshController {
  void init(dynamic id) {
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_pull_to_refresh_$id');
    handler = _handleMethod;
    initMethodCallHandler();
  }
}
