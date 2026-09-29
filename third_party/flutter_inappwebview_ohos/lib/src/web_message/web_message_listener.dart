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

WebMessage? parseOhosPlatformWebMessage(Map<String, dynamic>? messageMap) {
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

/// Object specifying creation parameters for creating a [OhosWebMessageListener].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformWebMessageListenerCreationParams] for
/// more information.
@immutable
class OhosWebMessageListenerCreationParams
    extends PlatformWebMessageListenerCreationParams {
  /// Creates a new [OhosWebMessageListenerCreationParams] instance.
  const OhosWebMessageListenerCreationParams(
      {required this.allowedOriginRules,
      required super.jsObjectName,
      super.onPostMessage});

  /// Creates a [OhosWebMessageListenerCreationParams] instance based on [PlatformWebMessageListenerCreationParams].
  factory OhosWebMessageListenerCreationParams.fromPlatformWebMessageListenerCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformWebMessageListenerCreationParams params) {
    return OhosWebMessageListenerCreationParams(
        allowedOriginRules: params.allowedOriginRules ?? Set.from(["*"]),
        jsObjectName: params.jsObjectName,
        onPostMessage: params.onPostMessage);
  }

  @override
  final Set<String> allowedOriginRules;

  @override
  String toString() {
    return 'OhosWebMessageListenerCreationParams{jsObjectName: $jsObjectName, allowedOriginRules: $allowedOriginRules, onPostMessage: $onPostMessage}';
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformWebMessageListener}
class OhosWebMessageListener extends PlatformWebMessageListener
    with ChannelController {
  /// Constructs a [OhosWebMessageListener].
  OhosWebMessageListener(PlatformWebMessageListenerCreationParams params)
      : super.implementation(
          params is OhosWebMessageListenerCreationParams
              ? params
              : OhosWebMessageListenerCreationParams
                  .fromPlatformWebMessageListenerCreationParams(params),
        ) {
    assert(!this._OhosParams.allowedOriginRules.contains(""),
        "allowedOriginRules cannot contain empty strings");
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_web_message_listener_${_id}_${params.jsObjectName}');
    handler = _handleMethod;
    initMethodCallHandler();
  }

  ///Message Listener ID used internally.
  final String _id = IdGenerator.generate();

  OhosJavaScriptReplyProxy? _replyProxy;

  OhosWebMessageListenerCreationParams get _OhosParams =>
      params as OhosWebMessageListenerCreationParams;

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case "onPostMessage":
        if (_replyProxy == null) {
          _replyProxy = OhosJavaScriptReplyProxy(
              PlatformJavaScriptReplyProxyCreationParams(
                  webMessageListener: this));
        }
        if (onPostMessage != null) {
          final rawMessage = call.arguments['message'];
          final messageMap = rawMessage == null
              ? null
              : Map<String, dynamic>.from(rawMessage as Map);
          final message = parseOhosPlatformWebMessage(messageMap);
          WebUri? sourceOrigin = call.arguments["sourceOrigin"] != null
              ? WebUri(call.arguments["sourceOrigin"])
              : null;
          bool isMainFrame = call.arguments["isMainFrame"];
          onPostMessage!(message, sourceOrigin, isMainFrame, _replyProxy!);
        }
        break;
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
    return null;
  }

  @override
  void dispose() {
    if (disposed) {
      return;
    }
    disposeChannel();
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      "id": _id,
      "jsObjectName": params.jsObjectName,
      "allowedOriginRules": _OhosParams.allowedOriginRules.toList(),
    };
  }

  @override
  Map<String, dynamic> toJson() {
    return this.toMap();
  }

  @override
  String toString() {
    return 'OhosWebMessageListener{id: ${_id}, jsObjectName: ${params.jsObjectName}, allowedOriginRules: ${params.allowedOriginRules}, replyProxy: $_replyProxy}';
  }
}

/// Object specifying creation parameters for creating a [OhosJavaScriptReplyProxy].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformJavaScriptReplyProxyCreationParams] for
/// more information.
@immutable
class OhosJavaScriptReplyProxyCreationParams
    extends PlatformJavaScriptReplyProxyCreationParams {
  /// Creates a new [OhosJavaScriptReplyProxyCreationParams] instance.
  const OhosJavaScriptReplyProxyCreationParams(
      {required super.webMessageListener});

  /// Creates a [OhosJavaScriptReplyProxyCreationParams] instance based on [PlatformJavaScriptReplyProxyCreationParams].
  factory OhosJavaScriptReplyProxyCreationParams.fromPlatformJavaScriptReplyProxyCreationParams(
      // Recommended placeholder to prevent being broken by platform interface.
      // ignore: avoid_unused_constructor_parameters
      PlatformJavaScriptReplyProxyCreationParams params) {
    return OhosJavaScriptReplyProxyCreationParams(
        webMessageListener: params.webMessageListener);
  }
}

///{@macro flutter_inappwebview_platform_interface.JavaScriptReplyProxy}
class OhosJavaScriptReplyProxy extends PlatformJavaScriptReplyProxy {
  /// Constructs a [OhosWebMessageListener].
  OhosJavaScriptReplyProxy(PlatformJavaScriptReplyProxyCreationParams params)
      : super.implementation(
          params is OhosJavaScriptReplyProxyCreationParams
              ? params
              : OhosJavaScriptReplyProxyCreationParams
                  .fromPlatformJavaScriptReplyProxyCreationParams(params),
        );

  OhosWebMessageListener get _OhosWebMessageListener =>
      params.webMessageListener as OhosWebMessageListener;

  @override
  Future<void> postMessage(WebMessage message) async {
    dynamic data = message.data;
    if (message.type == WebMessageType.ARRAY_BUFFER && data is Uint8List) {
      // MethodChannel on OHOS may drop Uint8List; send a plain List<int> instead.
      data = data.toList();
    }
    await _OhosWebMessageListener.channel?.invokeMethod('postMessage', {
      'data': data,
      'type': message.type.toNativeValue(),
    });
  }

  @override
  String toString() {
    return 'OhosJavaScriptReplyProxy{}';
  }
}
