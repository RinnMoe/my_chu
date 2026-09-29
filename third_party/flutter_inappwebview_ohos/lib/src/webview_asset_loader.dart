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

/// Object specifying creation parameters for creating a [OhosPathHandler].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformPathHandlerCreationParams] for
/// more information.
@immutable
class OhosPathHandlerCreationParams
    extends PlatformPathHandlerCreationParams {
  /// Creates a new [OhosPathHandlerCreationParams] instance.
  OhosPathHandlerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformPathHandlerCreationParams params,
  ) : super(path: params.path);

  /// Creates a [OhosPathHandlerCreationParams] instance based on [PlatformPathHandlerCreationParams].
  factory OhosPathHandlerCreationParams.fromPlatformPathHandlerCreationParams(
      PlatformPathHandlerCreationParams params) {
    return OhosPathHandlerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformPathHandler}
abstract mixin class OhosPathHandler
    implements ChannelController, PlatformPathHandler {
  final String _id = IdGenerator.generate();

  @override
  late final PlatformPathHandlerEvents? eventHandler;

  @override
  late final String path;

  void _init(PlatformPathHandlerCreationParams params) {
    this.path = params.path;
    channel = MethodChannel(
        'com.pichillilorenzo/flutter_inappwebview_custompathhandler_${_id}');
    handler = _handleMethod;
    initMethodCallHandler();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case "handle":
        String path = call.arguments["path"];
        return (await eventHandler?.handle(path))?.toMap();
      default:
        throw UnimplementedError("Unimplemented ${call.method} method");
    }
  }

  @override
  Map<String, dynamic> toMap() {
    return {"path": path, "type": type, "id": _id};
  }

  @override
  Map<String, dynamic> toJson() {
    return toMap();
  }

  @override
  String toString() {
    return 'OhosPathHandler{path: $path, type: $type}';
  }

  @override
  void dispose() {
    disposeChannel();
    eventHandler = null;
  }
}

/// Object specifying creation parameters for creating a [OhosAssetsPathHandler].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformAssetsPathHandlerCreationParams] for
/// more information.
@immutable
class OhosAssetsPathHandlerCreationParams
    extends PlatformAssetsPathHandlerCreationParams {
  /// Creates a new [OhosAssetsPathHandlerCreationParams] instance.
  OhosAssetsPathHandlerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformAssetsPathHandlerCreationParams params,
  ) : super(params);

  /// Creates a [OhosAssetsPathHandlerCreationParams] instance based on [PlatformAssetsPathHandlerCreationParams].
  factory OhosAssetsPathHandlerCreationParams.fromPlatformAssetsPathHandlerCreationParams(
      PlatformAssetsPathHandlerCreationParams params) {
    return OhosAssetsPathHandlerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformAssetsPathHandler}
class OhosAssetsPathHandler extends PlatformAssetsPathHandler
    with OhosPathHandler, ChannelController {
  /// Constructs a [OhosAssetsPathHandler].
  OhosAssetsPathHandler(PlatformAssetsPathHandlerCreationParams params)
      : super.implementation(
          params is OhosAssetsPathHandlerCreationParams
              ? params
              : OhosAssetsPathHandlerCreationParams
                  .fromPlatformAssetsPathHandlerCreationParams(params),
        ) {
    _init(params);
  }
}

/// Object specifying creation parameters for creating a [OhosResourcesPathHandler].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformResourcesPathHandlerCreationParams] for
/// more information.
@immutable
class OhosResourcesPathHandlerCreationParams
    extends PlatformResourcesPathHandlerCreationParams {
  /// Creates a new [OhosResourcesPathHandlerCreationParams] instance.
  OhosResourcesPathHandlerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformResourcesPathHandlerCreationParams params,
  ) : super(params);

  /// Creates a [OhosResourcesPathHandlerCreationParams] instance based on [PlatformResourcesPathHandlerCreationParams].
  factory OhosResourcesPathHandlerCreationParams.fromPlatformResourcesPathHandlerCreationParams(
      PlatformResourcesPathHandlerCreationParams params) {
    return OhosResourcesPathHandlerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformResourcesPathHandler}
class OhosResourcesPathHandler extends PlatformResourcesPathHandler
    with OhosPathHandler, ChannelController {
  /// Constructs a [OhosResourcesPathHandler].
  OhosResourcesPathHandler(PlatformResourcesPathHandlerCreationParams params)
      : super.implementation(
          params is OhosResourcesPathHandlerCreationParams
              ? params
              : OhosResourcesPathHandlerCreationParams
                  .fromPlatformResourcesPathHandlerCreationParams(params),
        ) {
    _init(params);
  }
}

/// Object specifying creation parameters for creating a [OhosInternalStoragePathHandler].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformInternalStoragePathHandlerCreationParams] for
/// more information.
@immutable
class OhosInternalStoragePathHandlerCreationParams
    extends PlatformInternalStoragePathHandlerCreationParams {
  /// Creates a new [OhosInternalStoragePathHandlerCreationParams] instance.
  OhosInternalStoragePathHandlerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformInternalStoragePathHandlerCreationParams params,
  ) : super(params, directory: params.directory);

  /// Creates a [OhosInternalStoragePathHandlerCreationParams] instance based on [PlatformInternalStoragePathHandlerCreationParams].
  factory OhosInternalStoragePathHandlerCreationParams.fromPlatformInternalStoragePathHandlerCreationParams(
      PlatformInternalStoragePathHandlerCreationParams params) {
    return OhosInternalStoragePathHandlerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformInternalStoragePathHandler}
class OhosInternalStoragePathHandler
    extends PlatformInternalStoragePathHandler
    with OhosPathHandler, ChannelController {
  /// Constructs a [OhosInternalStoragePathHandler].
  OhosInternalStoragePathHandler(
      PlatformInternalStoragePathHandlerCreationParams params)
      : super.implementation(
          params is OhosInternalStoragePathHandlerCreationParams
              ? params
              : OhosInternalStoragePathHandlerCreationParams
                  .fromPlatformInternalStoragePathHandlerCreationParams(params),
        ) {
    _init(params);
  }

  OhosInternalStoragePathHandlerCreationParams get _internalParams =>
      params as OhosInternalStoragePathHandlerCreationParams;

  @override
  String get directory => _internalParams.directory;

  @override
  Map<String, dynamic> toMap() {
    // Must call mixin/super toMap — `{...toMap()}` recurses and Stack Overflows
    // (AssetsPathHandler + InternalStoragePathHandler integration test).
    return {...super.toMap(), 'directory': directory};
  }
}

/// Object specifying creation parameters for creating a [OhosCustomPathHandler].
///
/// When adding additional fields make sure they can be null or have a default
/// value to avoid breaking changes. See [PlatformCustomPathHandlerCreationParams] for
/// more information.
@immutable
class OhosCustomPathHandlerCreationParams
    extends PlatformCustomPathHandlerCreationParams {
  /// Creates a new [OhosCustomPathHandlerCreationParams] instance.
  OhosCustomPathHandlerCreationParams(
    // This parameter prevents breaking changes later.
    // ignore: avoid_unused_constructor_parameters
    PlatformCustomPathHandlerCreationParams params,
  ) : super(params);

  /// Creates a [OhosCustomPathHandlerCreationParams] instance based on [PlatformCustomPathHandlerCreationParams].
  factory OhosCustomPathHandlerCreationParams.fromPlatformCustomPathHandlerCreationParams(
      PlatformCustomPathHandlerCreationParams params) {
    return OhosCustomPathHandlerCreationParams(params);
  }
}

///{@macro flutter_inappwebview_platform_interface.PlatformCustomPathHandler}
class OhosCustomPathHandler extends PlatformCustomPathHandler
    with OhosPathHandler, ChannelController {
  /// Constructs a [OhosCustomPathHandler].
  OhosCustomPathHandler(PlatformCustomPathHandlerCreationParams params)
      : super.implementation(
          params is OhosCustomPathHandlerCreationParams
              ? params
              : OhosCustomPathHandlerCreationParams
                  .fromPlatformCustomPathHandlerCreationParams(params),
        ) {
    _init(params);
  }
}
