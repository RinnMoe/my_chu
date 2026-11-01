import 'dart:convert';

import 'package:flutter/services.dart';

import 'charging_pile_catalog_document.dart';
import 'charging_pile_http_client.dart';

/// 一份目录快照：解析结果 + 原文。
///
/// 原文要一起带回来，因为本机缓存存的就是站点那份 JSON 的原文，
/// 再序列化一遍只会引入格式漂移。
class ChargingPileCatalogSnapshot {
  const ChargingPileCatalogSnapshot({
    required this.document,
    required this.rawText,
  });

  final ChargingPileCatalogDocument document;
  final String rawText;
}

/// 目录快照的来源。
///
/// 三层结构：随包内置 → 本机缓存 → 站点目录。任何一层失败都不影响可用性，
/// 因为调用方永远先拿到上一层的快照。
abstract class ChargingPileCatalogSource {
  /// 诊断用的来源标签（不进 UI 正文）。
  String get label;

  Future<ChargingPileCatalogSnapshot> load();

  void close();
}

/// 随包内置快照。严格解析：随包数据必须是自洽的，否则在开发期就暴露。
class BundledChargingPileCatalogSource implements ChargingPileCatalogSource {
  BundledChargingPileCatalogSource({AssetBundle? bundle})
    : _bundle = bundle ?? rootBundle;

  final AssetBundle _bundle;

  @override
  String get label => 'bundled';

  @override
  Future<ChargingPileCatalogSnapshot> load() async {
    final text = await _bundle.loadString(ChargingPileCatalogDocument.assetPath);
    return ChargingPileCatalogSnapshot(
      document: ChargingPileCatalogDocument.parse(text),
      rawText: text,
    );
  }

  @override
  void close() {}
}

/// 直接读站点发布的 `catalog.json`。
///
/// 站点把设备清单、分区和坐标摊平成了这一份静态 JSON（契约见站点仓库
/// `docs/API.md`）。它随站点部署更新，所以这条路径让「站点加桩 → App
/// 自动跟上」不再需要发版。
class RemoteChargingPileCatalogSource implements ChargingPileCatalogSource {
  RemoteChargingPileCatalogSource({
    ChargingPileHttpClient? httpClient,
    Uri? uri,
    this.timeout = const Duration(seconds: 8),
    this.maxBytes = 512 * 1024,
  }) : _http = httpClient ?? ChargingPileHttpClient(),
       _ownsClient = httpClient == null,
       _uri = uri ?? ChargingPileCatalogDocument.remoteUri;

  final ChargingPileHttpClient _http;
  final bool _ownsClient;
  final Uri _uri;
  final Duration timeout;
  final int maxBytes;

  @override
  String get label => 'remote';

  @override
  Future<ChargingPileCatalogSnapshot> load() async {
    final response = await _http.get(_uri, timeout: timeout);
    if (response.statusCode != 200) {
      throw ChargingPileCatalogException(
        ChargingPileCatalogFailure.missingField,
        '目录返回 HTTP ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > maxBytes) {
      throw const ChargingPileCatalogException(
        ChargingPileCatalogFailure.invalidValue,
        '目录超过大小上限',
      );
    }
    // 站点目录是 UTF-8 无 BOM 的 JSON；容忍少量非法字节比整份失败划算。
    final text = const Utf8Decoder(allowMalformed: true).convert(
      response.bodyBytes,
    );
    return ChargingPileCatalogSnapshot(
      // 远端数据比客户端新是常态，用宽容解析。
      document: ChargingPileCatalogDocument.parse(
        text,
        strictness: ChargingPileCatalogStrictness.tolerant,
      ),
      rawText: text,
    );
  }

  @override
  void close() {
    if (_ownsClient) _http.close();
  }
}
