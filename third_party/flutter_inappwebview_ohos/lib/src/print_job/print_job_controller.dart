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

/// Object specifying creation parameters for creating a [OhosPrintJobController].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformPrintJobControllerCreationParams] for
/// more information.
@immutable
class OhosPrintJobControllerCreationParams
    extends PlatformPrintJobControllerCreationParams {
  /// Creates a new [OhosPrintJobControllerCreationParams] instance.
  const OhosPrintJobControllerCreationParams(
      {required super.id, super.onComplete});

  /// Creates a [OhosPrintJobControllerCreationParams] instance based on [PlatformPrintJobControllerCreationParams].
  factory OhosPrintJobControllerCreationParams.fromPlatformPrintJobControllerCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformPrintJobControllerCreationParams params) {
    return OhosPrintJobControllerCreationParams(
        id: params.id, onComplete: params.onComplete);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformPrintJobController}
class OhosPrintJobController extends PlatformPrintJobController
    with ChannelController {
  /// Constructs a [OhosPrintJobController].
  OhosPrintJobController(PlatformPrintJobControllerCreationParams params)
      : super.implementation(
          params is OhosPrintJobControllerCreationParams
              ? params
              : OhosPrintJobControllerCreationParams
                  .fromPlatformPrintJobControllerCreationParams(params),
        ) {
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_printjobcontroller_${params.id}');
    handler = _handleMethod;
    initMethodCallHandler();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
  }

  @override
  Future<void> cancel() async {
    Map<String, dynamic> args = <String, dynamic>{};
    await channel?.invokeMethod('cancel', args);
  }

  @override
  Future<void> restart() async {
    Map<String, dynamic> args = <String, dynamic>{};
    await channel?.invokeMethod('restart', args);
  }

  @override
  Future<void> dismiss({bool animated = true}) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent("animated", () => animated);
    await channel?.invokeMethod('dismiss', args);
  }

  @override
  Future<PrintJobInfo?> getInfo() async {
    Map<String, dynamic> args = <String, dynamic>{};
    Map<String, dynamic>? infoMap =
        (await channel?.invokeMethod('getInfo', args))?.cast<String, dynamic>();
    return PrintJobInfo.fromMap(infoMap);
  }

  @override
  Future<void> dispose() async {
    Map<String, dynamic> args = <String, dynamic>{};
    await channel?.invokeMethod('dispose', args);
    disposeChannel();
  }
}
