import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:http/http.dart" as http;
import "package:path_provider/path_provider.dart";
import "package:shared_preferences/shared_preferences.dart";

import "../mapbox_cloud_config.dart";
import "campus_places_models.dart";
import "campus_registry.dart";
import "place_code_rule_overrides.dart";

/// The namespaced semantic catalog stored in a Mapbox Classic Style.
///
/// Only these content fields participate in [contentSha256]. Release
/// timestamps and the derived release id are deliberately excluded so
/// rebuilding unchanged repository assets does not create a fake release.
const List<String> semanticCatalogContentKeys = <String>[
  "campuses",
  "placeCodeRules",
  "labelOverrides",
  "placesByCampus",
  "labelsByCampus",
];

/// A parsed semantic catalog header.
class MapReleaseManifest {
  final int schemaVersion;
  final String releaseId;
  final DateTime? publishedAt;
  final int minimumClientSchema;
  final String contentSha256;
  final Map<String, dynamic> raw;

  const MapReleaseManifest({
    required this.schemaVersion,
    required this.releaseId,
    required this.minimumClientSchema,
    required this.contentSha256,
    required this.raw,
    this.publishedAt,
  });

  factory MapReleaseManifest.fromJson(Map<String, dynamic> json) {
    return MapReleaseManifest(
      schemaVersion: _number(json["schemaVersion"]) ?? 0,
      releaseId: _text(json["releaseId"]),
      publishedAt: DateTime.tryParse(_text(json["publishedAt"])),
      minimumClientSchema:
          _number(json["minimumClientSchema"]) ??
          _number(json["schemaVersion"]) ??
          0,
      contentSha256: _text(json["contentSha256"]).toLowerCase(),
      raw: Map<String, dynamic>.unmodifiable(json),
    );
  }
}

/// A complete, internally consistent runtime snapshot.
class MapReleaseSnapshot {
  final MapReleaseManifest manifest;
  final CampusRegistry registry;
  final Map<String, CampusPlacesData> placesByCampus;
  final PlaceCodeRuleCatalog codeRules;

  const MapReleaseSnapshot({
    required this.manifest,
    required this.registry,
    required this.placesByCampus,
    required this.codeRules,
  });
}

class MapReleaseUnavailable implements Exception {
  final String message;
  const MapReleaseUnavailable(this.message);

  @override
  String toString() => message;
}

class _BoundedHttpResponse {
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List bodyBytes;

  const _BoundedHttpResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
  });
}

/// Reads and stages MyCHU's semantic catalog from the Mapbox Published Style.
///
/// Mapbox owns the visual style, basemap, tiles, glyphs and sprites. This
/// repository only reads the namespaced semantic metadata and never requests
/// a self-hosted release manifest or per-resource URL.
class MapReleaseRepository {
  static const int clientSchema = 5;
  static const String semanticMetadataKey =
      MapboxCloudConfig.semanticMetadataKey;
  static const int maxStyleBytes = 1000000;
  static const int maxPointerBytes = 256;
  static const String activePointer = "active.json";
  static const String pendingPointer = "pending.json";
  static const String etagKey = "mapbox.semantic.style.etag.v1";
  static const String checkedAtKey = "mapbox.semantic.style.checked_at.v1";

  final http.Client client;
  final Future<Directory> Function() directoryProvider;
  final Future<SharedPreferences> Function() preferences;
  final Uri? configuredStyleApiUri;
  final String? configuredAccessToken;
  final Map<String, dynamic> _memory = <String, dynamic>{};

  MapReleaseRepository({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? preferences,
    Uri? styleApiUri,
    String? accessToken,
  }) : client = client ?? http.Client(),
       directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       preferences = preferences ?? SharedPreferences.getInstance,
       configuredStyleApiUri = styleApiUri,
       configuredAccessToken = accessToken;

  MapReleaseSnapshot? get activeSnapshot =>
      _memory["active"] as MapReleaseSnapshot?;

  /// The one Published Style endpoint used by production runtime reads.
  Uri get publishedStyleApiUri => _styleRequestUri();

  Future<MapReleaseSnapshot> loadForStartup() async {
    final root = await _rootDirectory();
    await _activatePending(root);

    final activeId = await _readPointer(root, activePointer);
    if (activeId != null) {
      final snapshot = await _readSnapshot(root, activeId);
      if (snapshot != null) {
        _memory["active"] = snapshot;
        return snapshot;
      }
    }

    final snapshot = await _fetchAndActivate(root);
    _memory["active"] = snapshot;
    return snapshot;
  }

  /// Stages a changed Published Style semantic catalog without activating it.
  ///
  /// The active snapshot stays untouched until the next
  /// [loadForStartup], which prevents a background refresh from replacing the
  /// semantic graph while a visible map is using it.
  Future<bool> refresh() async {
    final root = await _rootDirectory();
    final store = await preferences();
    final headers = <String, String>{};
    final etag = store.getString(etagKey)?.trim() ?? "";
    if (etag.isNotEmpty) headers["If-None-Match"] = etag;

    final response = await _getBounded(
      _styleRequestUri(),
      headers: headers,
      maxBytes: maxStyleBytes,
      label: "Mapbox Published Style",
      timeout: const Duration(seconds: 12),
    );
    if (response.statusCode == 304) {
      await _recordCheck(store, response.headers["etag"] ?? etag);
      return false;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MapReleaseUnavailable(
        "Mapbox Published Style 请求失败：${response.statusCode}",
      );
    }

    final snapshot = await _decodeStyleSnapshot(response.bodyBytes);
    final currentId = await _readPointer(root, activePointer);
    final pendingId = await _readPointer(root, pendingPointer);
    if (snapshot.manifest.releaseId == currentId ||
        snapshot.manifest.releaseId == pendingId) {
      await _recordCheck(store, response.headers["etag"] ?? etag);
      return false;
    }

    await _persistSnapshot(root, snapshot);
    final persisted = await _readSnapshot(root, snapshot.manifest.releaseId);
    if (persisted == null) {
      throw const MapReleaseUnavailable("地图语义缓存解析失败");
    }
    await _writePointer(root, pendingPointer, snapshot.manifest.releaseId);
    await _recordCheck(store, response.headers["etag"] ?? etag);
    _memory["pending"] = persisted;
    return true;
  }

  Future<MapReleaseSnapshot> _fetchAndActivate(Directory root) async {
    final response = await _getBounded(
      _styleRequestUri(),
      maxBytes: maxStyleBytes,
      label: "Mapbox Published Style",
      timeout: const Duration(seconds: 12),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MapReleaseUnavailable(
        "Mapbox Published Style 请求失败：${response.statusCode}",
      );
    }
    final snapshot = await _decodeStyleSnapshot(response.bodyBytes);
    await _persistSnapshot(root, snapshot);
    final persisted = await _readSnapshot(root, snapshot.manifest.releaseId);
    if (persisted == null) {
      throw const MapReleaseUnavailable("地图语义缓存解析失败");
    }
    await _writePointer(root, activePointer, snapshot.manifest.releaseId);
    await _recordCheck(await preferences(), response.headers["etag"] ?? "");
    return persisted;
  }

  Future<void> _activatePending(Directory root) async {
    final pendingId = await _readPointer(root, pendingPointer);
    if (pendingId == null) return;
    final snapshot = await _readSnapshot(root, pendingId);
    if (snapshot == null) return;

    await _writePointer(root, activePointer, pendingId);
    await _writePointer(root, pendingPointer, "");
    _memory["active"] = snapshot;
    _memory.remove("pending");
  }

  Future<MapReleaseSnapshot?> _readSnapshot(
    Directory root,
    String releaseId,
  ) async {
    if (!_isSafeReleaseId(releaseId)) return null;
    final directory = Directory("${root.path}/releases/$releaseId");
    final semanticFile = File("${directory.path}/semantic.json");
    if (!await semanticFile.exists()) return null;
    try {
      final raw = jsonDecode(await semanticFile.readAsString(encoding: utf8));
      if (raw is! Map) return null;
      final catalog = Map<String, dynamic>.from(raw);
      return _decodeCatalog(catalog);
    } catch (_) {
      return null;
    }
  }

  Future<MapReleaseSnapshot> _decodeStyleSnapshot(Uint8List bodyBytes) async {
    try {
      final decoded = jsonDecode(utf8.decode(bodyBytes));
      if (decoded is! Map) {
        throw const MapReleaseUnavailable("Mapbox Style JSON 格式无效");
      }
      final style = Map<String, dynamic>.from(decoded);
      final metadata = style["metadata"];
      if (metadata is! Map) {
        throw const MapReleaseUnavailable("Mapbox Style 缺少 metadata");
      }
      final semantic = metadata[semanticMetadataKey];
      if (semantic is! Map) {
        throw const MapReleaseUnavailable(
          "Mapbox Style 缺少 MyCHU semantic metadata",
        );
      }
      return _decodeCatalog(Map<String, dynamic>.from(semantic));
    } on MapReleaseUnavailable {
      rethrow;
    } catch (_) {
      throw const MapReleaseUnavailable("Mapbox semantic metadata 解析失败");
    }
  }

  MapReleaseSnapshot _decodeCatalog(Map<String, dynamic> json) {
    final manifest = MapReleaseManifest.fromJson(json);
    _validateCatalog(json, manifest);

    final campusesJson = Map<String, dynamic>.from(json["campuses"] as Map);
    final registry = CampusRegistry.fromJson(campusesJson);
    final rawPlaces = Map<String, dynamic>.from(json["placesByCampus"] as Map);
    final places = <String, CampusPlacesData>{};
    for (final campus in registry.enabledCampuses) {
      final raw = rawPlaces[campus.campusId];
      if (raw is! Map) {
        throw MapReleaseUnavailable("发布版本缺少启用校区：${campus.campusId}");
      }
      final data = CampusPlacesData.fromJson(
        Map<String, dynamic>.from(raw),
        expectedCampusId: campus.campusId,
      );
      places[campus.campusId] = data;
    }

    final rawLabels = json["labelsByCampus"];
    if (rawLabels != null) {
      if (rawLabels is! Map) {
        throw const MapReleaseUnavailable("标签数据格式无效");
      }
      for (final entry in rawLabels.entries) {
        final campusId = entry.key;
        if (campusId is! String || registry.byId(campusId) == null) {
          throw const MapReleaseUnavailable("标签数据包含未知校区");
        }
        if (entry.value is! Map) {
          throw MapReleaseUnavailable("标签数据格式无效：$campusId");
        }
      }
    }

    final codeRules = PlaceCodeRulesRepository.decodeCatalog(
      jsonEncode(json["placeCodeRules"]),
    );
    return MapReleaseSnapshot(
      manifest: manifest,
      registry: registry,
      placesByCampus: Map.unmodifiable(places),
      codeRules: codeRules,
    );
  }

  Future<void> _persistSnapshot(
    Directory root,
    MapReleaseSnapshot snapshot,
  ) async {
    final releaseId = snapshot.manifest.releaseId;
    final target = Directory("${root.path}/releases/$releaseId");
    final existing = await _readSnapshot(root, releaseId);
    if (existing != null &&
        existing.manifest.contentSha256 == snapshot.manifest.contentSha256) {
      return;
    }
    if (await target.exists()) await target.delete(recursive: true);

    final staging = Directory(
      "${root.path}/staging-$releaseId-${DateTime.now().microsecondsSinceEpoch}",
    );
    await staging.create(recursive: true);
    try {
      final semanticFile = File("${staging.path}/semantic.json");
      await semanticFile.writeAsString(
        jsonEncode(snapshot.manifest.raw),
        encoding: utf8,
        flush: true,
      );
      await staging.rename(target.path);
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      throw const MapReleaseUnavailable("地图语义缓存写入失败");
    }
  }

  Future<Directory> _rootDirectory() async {
    final root = Directory("${(await directoryProvider()).path}/mychu-map");
    await root.create(recursive: true);
    await Directory("${root.path}/releases").create(recursive: true);
    return root;
  }

  Future<String?> _readPointer(Directory root, String name) async {
    final file = File("${root.path}/$name");
    if (!await file.exists()) return null;
    try {
      final value = (await file.readAsString(encoding: utf8)).trim();
      if (value.length > maxPointerBytes) return null;
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writePointer(Directory root, String name, String value) async {
    final temp = File("${root.path}/.$name.tmp");
    await temp.writeAsString(value, encoding: utf8, flush: true);
    final target = File("${root.path}/$name");
    if (await target.exists()) await target.delete();
    await temp.rename(target.path);
  }

  Future<void> _recordCheck(SharedPreferences store, String etag) async {
    if (etag.isNotEmpty) await store.setString(etagKey, etag);
    await store.setInt(checkedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  Uri _styleRequestUri() {
    final token =
        (configuredAccessToken ?? MapboxCloudConfig.accessToken).trim();
    if (!token.startsWith("pk.") || token.length <= 3) {
      throw const MapReleaseUnavailable(
        "Mapbox semantic reads require a public pk.* token",
      );
    }
    try {
      final base =
          configuredStyleApiUri ??
          MapboxCloudConfig.publishedStyleApiUri(token: token);
      final query = <String, String>{
        ...base.queryParameters,
        "access_token": token,
      };
      return base.replace(queryParameters: query);
    } on MapReleaseUnavailable {
      rethrow;
    } catch (_) {
      throw const MapReleaseUnavailable("Mapbox Published Style 地址无效");
    }
  }

  Future<_BoundedHttpResponse> _getBounded(
    Uri uri, {
    Map<String, String>? headers,
    required int maxBytes,
    required String label,
    required Duration timeout,
  }) async {
    final request = http.Request("GET", uri);
    if (headers != null) request.headers.addAll(headers);
    final response = await client.send(request).timeout(timeout);
    final contentLength = response.contentLength;
    if (contentLength != null && contentLength > maxBytes) {
      await response.stream.listen(null).cancel();
      throw MapReleaseUnavailable("资源过大：$label");
    }

    final bytes = BytesBuilder(copy: false);
    var length = 0;
    await for (final chunk in response.stream.timeout(timeout)) {
      length += chunk.length;
      if (length > maxBytes) {
        throw MapReleaseUnavailable("资源过大：$label");
      }
      bytes.add(chunk);
    }
    return _BoundedHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      bodyBytes: bytes.takeBytes(),
    );
  }

  void _validateCatalog(
    Map<String, dynamic> json,
    MapReleaseManifest manifest,
  ) {
    if (manifest.schemaVersion != clientSchema ||
        manifest.minimumClientSchema > clientSchema) {
      throw const MapReleaseUnavailable("语义地图版本与当前 App 不兼容");
    }
    if (!_isSafeReleaseId(manifest.releaseId) ||
        !RegExp(r"^[a-f0-9]{64}$").hasMatch(manifest.contentSha256)) {
      throw const MapReleaseUnavailable("语义地图版本标识无效");
    }
    final expectedHash = _contentSha256(json);
    if (expectedHash != manifest.contentSha256 ||
        !manifest.releaseId.endsWith(expectedHash.substring(0, 16))) {
      throw const MapReleaseUnavailable("语义地图内容摘要校验失败");
    }
    if (manifest.publishedAt == null) {
      throw const MapReleaseUnavailable("语义地图缺少有效发布时间");
    }

    final campuses = json["campuses"];
    if (campuses is! Map || campuses["campuses"] is! List) {
      throw const MapReleaseUnavailable("校区注册表格式无效");
    }
    final ids = <String>{};
    for (final raw in campuses["campuses"] as List) {
      if (raw is! Map) {
        throw const MapReleaseUnavailable("校区记录格式无效");
      }
      final id = _text(raw["campus_id"]);
      if (id.isEmpty || !ids.add(id)) {
        throw const MapReleaseUnavailable("校区注册表包含重复或无效校区");
      }
    }

    final placeCodeRules = json["placeCodeRules"];
    if (placeCodeRules is! Map || placeCodeRules["rules"] is! List) {
      throw const MapReleaseUnavailable("编码规则格式无效");
    }
    for (final rawRule in placeCodeRules["rules"] as List) {
      if (rawRule is! Map ||
          _text(rawRule["id"]).isEmpty ||
          _text(rawRule["pattern"]).isEmpty ||
          _text(rawRule["campus_id"]).isEmpty) {
        throw const MapReleaseUnavailable("编码规则条目格式无效");
      }
    }
    final rawPrefixes = placeCodeRules["campusPrefixes"];
    if (rawPrefixes != null) {
      if (rawPrefixes is! List || rawPrefixes.any((raw) => raw is! Map)) {
        throw const MapReleaseUnavailable("校区编码前缀格式无效");
      }
    }
    if (json["labelOverrides"] is! Map) {
      throw const MapReleaseUnavailable("标签覆盖格式无效");
    }
    if (json["placesByCampus"] is! Map) {
      throw const MapReleaseUnavailable("地点数据格式无效");
    }
    final labels = json["labelsByCampus"];
    if (labels != null && labels is! Map) {
      throw const MapReleaseUnavailable("标签数据格式无效");
    }
  }

  static String _contentSha256(Map<String, dynamic> catalog) {
    final content = <String, dynamic>{
      for (final key in semanticCatalogContentKeys) key: catalog[key],
    };
    return sha256.convert(utf8.encode(_canonicalJson(content))).toString();
  }

  static String _canonicalJson(Object? value) {
    if (value is Map) {
      final entries =
          value.entries.map((entry) {
              if (entry.key is! String) {
                throw const FormatException("语义 JSON 键必须是字符串");
              }
              return MapEntry(entry.key as String, _canonicalJson(entry.value));
            }).toList()
            ..sort((a, b) => a.key.compareTo(b.key));
      return "{${entries.map((entry) => "${jsonEncode(entry.key)}:${entry.value}").join(",")}}";
    }
    if (value is List) {
      return "[${value.map(_canonicalJson).join(",")}]";
    }
    if (value is num && !value.isFinite) {
      throw const FormatException("语义 JSON 数字必须有限");
    }
    return jsonEncode(value);
  }

  static bool _isSafeReleaseId(String value) =>
      RegExp(r"^semantic-[a-f0-9]{16,64}$").hasMatch(value);
}

/// Account-independent coordinator for one immutable semantic snapshot.
class MapReleaseCoordinator {
  static final MapReleaseCoordinator shared = MapReleaseCoordinator();
  static const String bundledReleaseId = "bundled";

  final MapReleaseRepository repository;
  final CampusRegistryLoader registryLoader;
  final PlacesRepository placesRepository;
  final PlaceCodeRulesRepository codeRulesRepository;
  Future<MapReleaseSnapshot>? _startup;
  Future<bool>? _refreshInFlight;
  MapReleaseSnapshot? _activeSnapshot;
  bool _pendingActivation = false;

  MapReleaseCoordinator({
    MapReleaseRepository? repository,
    CampusRegistryLoader? registryLoader,
    PlacesRepository? placesRepository,
    PlaceCodeRulesRepository? codeRulesRepository,
  }) : repository = repository ?? MapReleaseRepository(),
       registryLoader = registryLoader ?? CampusRegistryLoader(),
       placesRepository = placesRepository ?? PlacesRepository(),
       codeRulesRepository = codeRulesRepository ?? PlaceCodeRulesRepository();

  MapReleaseSnapshot? get activeSnapshot =>
      _activeSnapshot ?? repository.activeSnapshot;

  /// Returns the currently active snapshot without advancing staged release
  /// activation. The first passive consumer may perform the initial
  /// acquisition, but later consumers share that active snapshot.
  Future<MapReleaseSnapshot> currentSnapshot() async {
    final active = _activeSnapshot ?? repository.activeSnapshot;
    if (active != null) {
      _activeSnapshot = active;
      return active;
    }
    return loadForStartup();
  }

  /// Loads the snapshot for a new map entry. A staged release is activated
  /// here, while an already active snapshot is reused until refresh stages a
  /// pending replacement.
  Future<MapReleaseSnapshot> loadForStartup() {
    final active = _activeSnapshot ?? repository.activeSnapshot;
    if (active != null && !_pendingActivation) {
      _activeSnapshot = active;
      return Future<MapReleaseSnapshot>.value(active);
    }
    final current = _startup;
    if (current != null) return current;
    final future = _loadStartup();
    _startup = future;
    return future;
  }

  Future<bool> refresh() {
    final current = _refreshInFlight;
    if (current != null) return current;
    final future = _refreshOnce();
    _refreshInFlight = future;
    return future;
  }

  Future<bool> _refreshOnce() async {
    try {
      final staged = await repository.refresh();
      if (staged) _pendingActivation = true;
      return staged;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<MapReleaseSnapshot> _loadStartup() async {
    try {
      final snapshot = await repository.loadForStartup();
      _activeSnapshot = snapshot;
      _pendingActivation = false;
      return snapshot;
    } catch (_) {
      final snapshot = await _loadBundledSnapshot();
      _activeSnapshot = snapshot;
      _pendingActivation = false;
      return snapshot;
    } finally {
      // A later startup call must be able to activate a staged pending
      // snapshot in the same process.
      _startup = null;
    }
  }

  Future<MapReleaseSnapshot> _loadBundledSnapshot() async {
    final registry = await registryLoader.load();
    final places = <String, CampusPlacesData>{};
    for (final campus in registry.enabledCampuses) {
      final data = await placesRepository.loadForCampus(campus);
      if (data != null) places[campus.campusId] = data;
    }
    return MapReleaseSnapshot(
      manifest: const MapReleaseManifest(
        schemaVersion: MapReleaseRepository.clientSchema,
        releaseId: bundledReleaseId,
        minimumClientSchema: MapReleaseRepository.clientSchema,
        contentSha256: "",
        raw: <String, dynamic>{
          "schemaVersion": MapReleaseRepository.clientSchema,
          "minimumClientSchema": MapReleaseRepository.clientSchema,
          "releaseId": bundledReleaseId,
        },
      ),
      registry: registry,
      placesByCampus: Map.unmodifiable(places),
      codeRules: await codeRulesRepository.loadCatalog(),
    );
  }
}

String _text(Object? value) => value is String ? value.trim() : "";
int? _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value));
