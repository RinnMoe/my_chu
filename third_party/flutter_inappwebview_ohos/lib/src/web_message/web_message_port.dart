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

import 'web_message_channel.dart';

/// Object specifying creation parameters for creating a [OhosWebMessagePort].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebMessagePortCreationParams] for
/// more information.
@immutable
class OhosWebMessagePortCreationParams
    extends PlatformWebMessagePortCreationParams {
  /// Creates a new [OhosWebMessagePortCreationParams] instance.
  const OhosWebMessagePortCreationParams({required super.index});

  /// Creates a [OhosWebMessagePortCreationParams] instance based on [PlatformWebMessagePortCreationParams].
  factory OhosWebMessagePortCreationParams.fromPlatformWebMessagePortCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformWebMessagePortCreationParams params) {
    return OhosWebMessagePortCreationParams(index: params.index);
  }

  @override
  String toString() {
    return 'OhosWebMessagePortCreationParams{index: $index}';
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformWebMessagePort}
class OhosWebMessagePort extends PlatformWebMessagePort {
  WebMessageCallback? _onMessage;
  late OhosWebMessageChannel _webMessageChannel;

  /// Constructs a [OhosWebMessagePort].
  OhosWebMessagePort(PlatformWebMessagePortCreationParams params)
      : super.implementation(
          params is OhosWebMessagePortCreationParams
              ? params
              : OhosWebMessagePortCreationParams
                  .fromPlatformWebMessagePortCreationParams(params),
        );

  @override
  Future<void> setWebMessageCallback(WebMessageCallback? onMessage) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('index', () => params.index);
    await _webMessageChannel.internalChannel
        ?.invokeMethod('setWebMessageCallback', args);
    this._onMessage = onMessage;
  }

  @override
  Future<void> postMessage(WebMessage message) async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('index', () => params.index);
    args.putIfAbsent('message', () => message.toMap());
    await _webMessageChannel.internalChannel?.invokeMethod('postMessage', args);
  }

  @override
  Future<void> close() async {
    Map<String, dynamic> args = <String, dynamic>{};
    args.putIfAbsent('index', () => params.index);
    await _webMessageChannel.internalChannel?.invokeMethod('close', args);
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      "index": params.index,
      "webMessageChannelId": this._webMessageChannel.params.id
    };
  }

  @override
  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return 'OhosWebMessagePort{index: ${params.index}}';
  }
}

extension InternalWebMessagePort on OhosWebMessagePort {
  WebMessageCallback? get onMessage => _onMessage;
  void set onMessage(WebMessageCallback? value) => _onMessage = value;

  OhosWebMessageChannel get webMessageChannel => _webMessageChannel;
  void set webMessageChannel(OhosWebMessageChannel value) =>
      _webMessageChannel = value;
}
