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

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'web_message_port.dart';

WebMessage? _parsePlatformWebMessage(Map<String, dynamic>? messageMap) {
  if (messageMap == null) {
    return null;
  }
  final type =
      WebMessageType.fromNativeValue(messageMap['type']) ?? WebMessageType.STRING;
  dynamic data = messageMap['data'];
  if (type == WebMessageType.ARRAY_BUFFER) {
    if (data is List) {
      data = Uint8List.fromList(data.cast<int>());
    }
  } else if (data != null && data is! String) {
    data = data.toString();
  }
  return WebMessage(data: data, type: type);
}

/// Object specifying creation parameters for creating a [OhosWebMessageChannel].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebMessageChannelCreationParams] for
/// more information.
@immutable
class OhosWebMessageChannelCreationParams
    extends PlatformWebMessageChannelCreationParams {
  /// Creates a new [OhosWebMessageChannelCreationParams] instance.
  const OhosWebMessageChannelCreationParams(
      {required super.id, required super.port1, required super.port2});

  /// Creates a [OhosWebMessageChannelCreationParams] instance based on [PlatformWebMessageChannelCreationParams].
  factory OhosWebMessageChannelCreationParams.fromPlatformWebMessageChannelCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformWebMessageChannelCreationParams params) {
    return OhosWebMessageChannelCreationParams(
        id: params.id, port1: params.port1, port2: params.port2);
  }

  @override
  String toString() {
    return 'OhosWebMessageChannelCreationParams{id: $id, port1: $port1, port2: $port2}';
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformWebMessageChannel}
class OhosWebMessageChannel extends PlatformWebMessageChannel
    with ChannelController {
  /// Constructs a [OhosWebMessageChannel].
  OhosWebMessageChannel(PlatformWebMessageChannelCreationParams params)
      : super.implementation(
          params is OhosWebMessageChannelCreationParams
              ? params
              : OhosWebMessageChannelCreationParams
                  .fromPlatformWebMessageChannelCreationParams(params),
        ) {
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_web_message_channel_${params.id}');
    handler = _handleMethod;
    initMethodCallHandler();
  }

  static final OhosWebMessageChannel _staticValue = OhosWebMessageChannel(
      OhosWebMessageChannelCreationParams(
          id: '',
          port1: OhosWebMessagePort(
              OhosWebMessagePortCreationParams(index: 0)),
          port2: OhosWebMessagePort(
              OhosWebMessagePortCreationParams(index: 1))));

  /// Provide static access.
  factory OhosWebMessageChannel.static() {
    return _staticValue;
  }

  OhosWebMessagePort get _OhosPort1 => port1 as OhosWebMessagePort;

  OhosWebMessagePort get _OhosPort2 => port2 as OhosWebMessagePort;

  static OhosWebMessageChannel? _fromMap(Map<String, dynamic>? map) {
    if (map == null) {
      return null;
    }
    var webMessageChannel = OhosWebMessageChannel(
        OhosWebMessageChannelCreationParams(
            id: map["id"],
            port1: OhosWebMessagePort(
                OhosWebMessagePortCreationParams(index: 0)),
            port2: OhosWebMessagePort(
                OhosWebMessagePortCreationParams(index: 1))));
    webMessageChannel._OhosPort1.webMessageChannel = webMessageChannel;
    webMessageChannel._OhosPort2.webMessageChannel = webMessageChannel;
    return webMessageChannel;
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case "onMessage":
        int index = call.arguments["index"];
        var port = index == 0 ? _OhosPort1 : _OhosPort2;
        if (port.onMessage != null) {
          final messageMap = call.arguments["message"] != null
              ? Map<String, dynamic>.from(
                  call.arguments["message"].cast<String, dynamic>())
              : null;
          port.onMessage!(_parsePlatformWebMessage(messageMap));
        }
        break;
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
    return null;
  }

  @override
  OhosWebMessageChannel? fromMap(Map<String, dynamic>? map) {
    return _fromMap(map);
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposeChannel();
  }

  @override
  String toString() {
    return 'OhosWebMessageChannel{id: $id, port1: $port1, port2: $port2}';
  }
}

extension InternalWebMessageChannel on OhosWebMessageChannel {
  MethodChannel? get internalChannel => channel;
}
