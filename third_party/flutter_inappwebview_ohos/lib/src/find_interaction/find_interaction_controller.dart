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
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';

/// Object specifying creation parameters for creating a [OhosFindInteractionController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformFindInteractionControllerCreationParams] for
/// more information.
@immutable
class OhosFindInteractionControllerCreationParams
    extends PlatformFindInteractionControllerCreationParams {
  /// Creates a new [OhosFindInteractionControllerCreationParams] instance.
  const OhosFindInteractionControllerCreationParams(
      {super.onFindResultReceived});

  /// Creates a [OhosFindInteractionControllerCreationParams] instance based on [PlatformFindInteractionControllerCreationParams].
  factory OhosFindInteractionControllerCreationParams.fromPlatformFindInteractionControllerCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformFindInteractionControllerCreationParams params) {
    return OhosFindInteractionControllerCreationParams(
        onFindResultReceived: params.onFindResultReceived);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController}
class OhosFindInteractionController extends PlatformFindInteractionController
    with ChannelController {
  /// Constructs a [OhosFindInteractionController].
  OhosFindInteractionController(
      PlatformFindInteractionControllerCreationParams params)
      : super.implementation(
          params is OhosFindInteractionControllerCreationParams
              ? params
              : OhosFindInteractionControllerCreationParams
                  .fromPlatformFindInteractionControllerCreationParams(params),
        );

  _debugLog(String method, dynamic args) {
    debugLog(
        className: this.runtimeType.toString(),
        debugLoggingSettings:
            PlatformFindInteractionController.debugLoggingSettings,
        method: method,
        args: args);
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    _debugLog(call.method, call.arguments);

    switch (call.method) {
      case "onFindResultReceived":
        if (onFindResultReceived != null) {
          int activeMatchOrdinal = call.arguments["activeMatchOrdinal"];
          int numberOfMatches = call.arguments["numberOfMatches"];
          bool isDoneCounting = call.arguments["isDoneCounting"];
          onFindResultReceived!(
              this, activeMatchOrdinal, numberOfMatches, isDoneCounting);
        }
        break;
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
    return null;
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.findAll}
  Future<void> findAll({String? find}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('find', () => find);
    await channel?.invokeMethod('findAll', args);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.findNext}
  Future<void> findNext({bool forward = true}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('forward', () => forward);
    await channel?.invokeMethod('findNext', args);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.clearMatches}
  Future<void> clearMatches() async {
    Map<String, dynamic> args = <String, dynamic>{};
    await channel?.invokeMethod('clearMatches', args);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.setSearchText}
  Future<void> setSearchText(String? searchText) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('searchText', () => searchText);
    await channel?.invokeMethod('setSearchText', args);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.getSearchText}
  Future<String?> getSearchText() async {
    Map<String, dynamic> args = <String, dynamic>{};
    return await channel?.invokeMethod<String?>('getSearchText', args);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.getActiveFindSession}
  Future<FindSession?> getActiveFindSession() async {
    Map<String, dynamic> args = <String, dynamic>{};
    Map<String, dynamic>? result =
        (await channel?.invokeMethod('getActiveFindSession', args))
            ?.cast<String, dynamic>();
    return FindSession.fromMap(result);
  }

  ///{@macro flutter_inappwebview_platform_interface.PlatformFindInteractionController.dispose}
  @override
  void dispose({bool isKeepAlive = false}) {
    disposeChannel(removeMethodCallHandler: !isKeepAlive);
  }
}

extension InternalFindInteractionController
    on OhosFindInteractionController {
  void init(dynamic id) {
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_find_interaction_$id');
    handler = _handleMethod;
    initMethodCallHandler();
  }
}
