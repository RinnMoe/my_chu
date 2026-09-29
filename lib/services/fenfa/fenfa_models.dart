const kFenfaFeedbackMaxContentLength = 4000;
const kFenfaFeedbackWithDiagnosticsMaxContentLength = 2700;
const kFenfaFeedbackMaxDiagnosticLength = 1200;
const kFenfaFeedbackMaxContactLength = 255;

/// latest 接口返回的产品上下文与发布信息。
class FenfaLatestSnapshot {
  final String? productId;
  final String? variantId;
  final String? variantPlatform;
  final FenfaRelease? release;

  const FenfaLatestSnapshot({
    this.productId,
    this.variantId,
    this.variantPlatform,
    this.release,
  });

  factory FenfaLatestSnapshot.fromJson(Map<String, dynamic> json) {
    final product = json['product'];
    final variant = json['variant'];
    final release = json['release'];

    return FenfaLatestSnapshot(
      productId: _optionalNonEmptyString(product, 'id'),
      variantId: _optionalNonEmptyString(variant, 'id'),
      variantPlatform: _optionalNonEmptyString(variant, 'platform'),
      release:
          release is Map<String, dynamic>
              ? FenfaRelease.fromJson(release)
              : null,
    );
  }
}

String? _optionalNonEmptyString(Object? value, String key) {
  if (value is! Map<String, dynamic>) return null;
  final field = value[key];
  return field is String && field.isNotEmpty ? field : null;
}

/// 匿名反馈类型；对应 Fenfa API 的 `category` 字段。
enum FenfaFeedbackCategory { bug, suggestion, other }

extension FenfaFeedbackCategoryValue on FenfaFeedbackCategory {
  String get apiValue => switch (this) {
    FenfaFeedbackCategory.bug => 'bug',
    FenfaFeedbackCategory.suggestion => 'suggestion',
    FenfaFeedbackCategory.other => 'other',
  };
}

/// 匿名反馈草稿；不包含账号、Cookie 或其他凭据。
class FenfaFeedbackDraft {
  final FenfaFeedbackCategory category;
  final String content;
  final String contact;
  final String diagnosticLog;

  const FenfaFeedbackDraft({
    required this.category,
    required this.content,
    this.contact = '',
    this.diagnosticLog = '',
  });
}

/// Fenfa 发布信息（latest 接口 `data.release`）。
class FenfaRelease {
  final String id;
  final String version;
  final int build;
  final String changelog;
  final bool forceUpdate;
  final String downloadUrl;
  final String? releasePage;
  final String? channel;
  final String? minOs;

  const FenfaRelease({
    required this.id,
    required this.version,
    required this.build,
    required this.changelog,
    required this.forceUpdate,
    required this.downloadUrl,
    this.releasePage,
    this.channel,
    this.minOs,
  });

  /// 防御性解析：必填字段缺失/类型错误抛 [FormatException]。
  factory FenfaRelease.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final version = json['version'];
    final build = json['build'];
    final forceUpdate = json['force_update'];
    final downloadUrl = json['download_url'];
    if (id is! String ||
        id.isEmpty ||
        version is! String ||
        version.isEmpty ||
        build is! num ||
        forceUpdate is! bool ||
        downloadUrl is! String ||
        downloadUrl.isEmpty) {
      throw const FormatException('Fenfa release 字段缺失或非法');
    }
    return FenfaRelease(
      id: id,
      version: version,
      build: build.toInt(),
      changelog: json['changelog'] is String ? json['changelog'] as String : '',
      forceUpdate: forceUpdate,
      downloadUrl: downloadUrl,
      releasePage:
          json['release_page'] is String
              ? json['release_page'] as String
              : null,
      channel: json['channel'] is String ? json['channel'] as String : null,
      minOs: json['min_os'] is String ? json['min_os'] as String : null,
    );
  }
}

/// Fenfa 公告（announcements 接口 `data.items` 单条）。
class FenfaAnnouncement {
  final String id;
  final String title;
  final String content;

  const FenfaAnnouncement({
    required this.id,
    required this.title,
    required this.content,
  });

  factory FenfaAnnouncement.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final content = json['content'];
    if (id is! String || id.isEmpty || title is! String || title.isEmpty) {
      throw const FormatException('Fenfa announcement 字段缺失或非法');
    }
    return FenfaAnnouncement(
      id: id,
      title: title,
      content: content is String ? content : '',
    );
  }
}
