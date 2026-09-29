import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import 'east8_time.dart';

/// Keeps compact text within the Android Status Chip's short-text budget.
String? truncateLiveUpdateChipText(String value) {
  final text = value.trim();
  if (text.isEmpty) return null;
  return String.fromCharCodes(text.runes.take(7));
}

/// The content state produced by a feature's Live Update loader.
enum LiveUpdateContentState { active, inactive, signedOut, error }

/// Common lifecycle phase consumed by Android Live Updates and Apple Live
/// Activities. The host still owns platform-specific rendering.
enum LiveUpdatePhase { upcoming, active, ended }

/// The exact text and native controls to render.
///
/// This is the plugin-facing contract for system Live Updates/Live Activities. A plugin
/// provides the display payload and optional boundary renders; the host owns
/// native notification construction, scheduling, persistence, and cleanup.
@immutable
class LiveUpdateRender {
  final String title;
  final String body;
  final String? shortCriticalText;
  final String? trackerEmoji;
  final DateTime? countdownAt;
  final int progress;
  final int progressMax;
  final bool requestPromoted;
  final bool ongoing;
  final DateTime? validUntil;
  final LiveUpdatePhase phase;
  final DateTime? startAt;
  final DateTime? endAt;

  const LiveUpdateRender({
    required this.title,
    required this.body,
    this.shortCriticalText,
    this.trackerEmoji,
    this.countdownAt,
    required this.progress,
    required this.progressMax,
    required this.requestPromoted,
    this.ongoing = true,
    this.validUntil,
    this.phase = LiveUpdatePhase.active,
    this.startAt,
    this.endAt,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    if (shortCriticalText != null && shortCriticalText!.isNotEmpty)
      'shortCriticalText': shortCriticalText,
    if (trackerEmoji != null && trackerEmoji!.isNotEmpty)
      'trackerEmoji': trackerEmoji,
    if (countdownAt != null) 'countdownAt': countdownAt!.toIso8601String(),
    'progress': progress,
    'progressMax': progressMax,
    'requestPromoted': requestPromoted,
    'ongoing': ongoing,
    if (validUntil != null) 'validUntil': validUntil!.toIso8601String(),
    'phase': phase.name,
    if (startAt != null) 'startAt': startAt!.toIso8601String(),
    if (endAt != null) 'endAt': endAt!.toIso8601String(),
  };

  factory LiveUpdateRender.fromJson(Map<String, dynamic> json) {
    return LiveUpdateRender(
      title: _string(json, 'title'),
      body: _string(json, 'body'),
      shortCriticalText:
          json['shortCriticalText'] is String
              ? json['shortCriticalText'] as String
              : null,
      trackerEmoji:
          json['trackerEmoji'] is String
              ? json['trackerEmoji'] as String
              : null,
      countdownAt:
          json['countdownAt'] is String
              ? DateTime.tryParse(json['countdownAt'] as String)
              : null,
      progress: _int(json, 'progress'),
      progressMax: _int(json, 'progressMax'),
      requestPromoted: json['requestPromoted'] == true,
      ongoing: json['ongoing'] != false,
      validUntil:
          json['validUntil'] is String
              ? DateTime.tryParse(json['validUntil'] as String)
              : null,
      phase: LiveUpdatePhase.values.firstWhere(
        (value) => value.name == json['phase'],
        orElse: () => LiveUpdatePhase.active,
      ),
      startAt:
          json['startAt'] is String
              ? DateTime.tryParse(json['startAt'] as String)
              : null,
      endAt:
          json['endAt'] is String
              ? DateTime.tryParse(json['endAt'] as String)
              : null,
    );
  }
}

/// One render to post when its alarm boundary fires.
@immutable
class LiveUpdateBoundaryRender {
  final DateTime at;
  final LiveUpdateRender render;
  final bool cancel;

  const LiveUpdateBoundaryRender({
    required this.at,
    required this.render,
    this.cancel = false,
  });

  Map<String, dynamic> toJson() => {
    'at': at.toIso8601String(),
    'render': render.toJson(),
    if (cancel) 'cancel': true,
  };

  factory LiveUpdateBoundaryRender.fromJson(Map<String, dynamic> json) {
    return LiveUpdateBoundaryRender(
      at: _dateTime(json, 'at'),
      render: LiveUpdateRender.fromJson(_map(json, 'render')),
      cancel: json['cancel'] == true,
    );
  }
}

/// Generic content produced by an app.
///
/// [render] is the current display payload. [boundaries] contain future
/// renders or cancellation points the host should handle when their alarm
/// fires. [postImmediately] controls whether the current render is posted
/// now or only scheduled. [cancelExisting] removes a previously posted
/// notification while retaining any future boundaries.
@immutable
class LiveUpdateContent {
  final LiveUpdateContentState state;
  final LiveUpdateRender render;
  final List<LiveUpdateBoundaryRender> boundaries;
  final bool postImmediately;
  final bool cancelExisting;
  final DateTime? validUntil;
  final DateTime generatedAt;

  const LiveUpdateContent({
    required this.state,
    required this.render,
    this.boundaries = const [],
    this.postImmediately = true,
    this.cancelExisting = false,
    this.validUntil,
    required this.generatedAt,
  });

  factory LiveUpdateContent.active({
    required LiveUpdateRender render,
    List<LiveUpdateBoundaryRender> boundaries = const [],
    bool postImmediately = true,
    DateTime? validUntil,
    DateTime? now,
    bool cancelExisting = false,
  }) {
    return LiveUpdateContent(
      state: LiveUpdateContentState.active,
      render: render,
      boundaries: boundaries,
      postImmediately: postImmediately,
      cancelExisting: cancelExisting,
      validUntil: validUntil,
      generatedAt: now ?? east8Now(),
    );
  }

  factory LiveUpdateContent.inactive({
    LiveUpdateRender? render,
    DateTime? now,
  }) {
    return LiveUpdateContent(
      state: LiveUpdateContentState.inactive,
      render: render ?? _placeholderRender('暂无内容'),
      postImmediately: false,
      cancelExisting: true,
      generatedAt: now ?? east8Now(),
    );
  }

  factory LiveUpdateContent.signedOut({DateTime? now}) {
    return LiveUpdateContent(
      state: LiveUpdateContentState.signedOut,
      render: _placeholderRender('登录 MyCHU 后使用'),
      postImmediately: false,
      cancelExisting: true,
      generatedAt: now ?? east8Now(),
    );
  }

  factory LiveUpdateContent.error({String? message, DateTime? now}) {
    return LiveUpdateContent(
      state: LiveUpdateContentState.error,
      render: _placeholderRender(message ?? '暂时无法获取内容'),
      postImmediately: false,
      cancelExisting: true,
      generatedAt: now ?? east8Now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'state': state.name,
    'render': render.toJson(),
    'boundaries': [for (final boundary in boundaries) boundary.toJson()],
    'postImmediately': postImmediately,
    'cancelExisting': cancelExisting,
    if (validUntil != null) 'validUntil': validUntil!.toIso8601String(),
    'generatedAt': generatedAt.toIso8601String(),
  };

  factory LiveUpdateContent.fromJson(Map<String, dynamic> json) {
    final rawBoundaries = json['boundaries'];
    return LiveUpdateContent(
      state: LiveUpdateContentState.values.firstWhere(
        (value) => value.name == json['state'],
        orElse: () => LiveUpdateContentState.inactive,
      ),
      render: LiveUpdateRender.fromJson(_map(json, 'render')),
      boundaries:
          rawBoundaries is List
              ? rawBoundaries
                  .whereType<Map<String, dynamic>>()
                  .map(LiveUpdateBoundaryRender.fromJson)
                  .toList(growable: false)
              : const [],
      postImmediately: json['postImmediately'] != false,
      cancelExisting: json['cancelExisting'] == true,
      validUntil:
          json['validUntil'] is String
              ? DateTime.tryParse(json['validUntil'] as String)
              : null,
      generatedAt:
          DateTime.tryParse(_string(json, 'generatedAt')) ?? east8Now(),
    );
  }
}

@immutable
class LiveUpdateLoadContext {
  final String accountKey;
  final DateTime now;
  final bool forceRefresh;

  const LiveUpdateLoadContext({
    required this.accountKey,
    required this.now,
    this.forceRefresh = false,
  });
}

typedef LiveUpdateContentLoader =
    Future<LiveUpdateContent> Function(LiveUpdateLoadContext context);

/// A feature's declarative contribution to a host system Live Update/Activity.
///
/// Any built-in app may register one or more definitions. The loader returns
/// generic renders and boundaries; it never touches notifications or native
/// scheduling.
@immutable
class SystemLiveActivityDefinition {
  final String id;
  final String title;
  final String targetAppId;
  final LiveUpdateContentLoader load;

  const SystemLiveActivityDefinition({
    required this.id,
    required this.title,
    required this.targetAppId,
    required this.load,
  });
}

/// The bounded payload sent to Android.
@immutable
class LiveUpdateNotificationPackage {
  final String accountKey;
  final String ownerGeneration;
  final String definitionId;
  final String targetAppId;
  final LiveUpdateRender render;
  final List<LiveUpdateBoundaryRender> boundaries;
  final bool isDemo;
  final bool postImmediately;
  final bool cancelExisting;

  const LiveUpdateNotificationPackage({
    required this.accountKey,
    this.ownerGeneration = '',
    required this.definitionId,
    required this.targetAppId,
    required this.render,
    this.boundaries = const [],
    this.isDemo = false,
    this.postImmediately = true,
    this.cancelExisting = false,
  });

  factory LiveUpdateNotificationPackage.fromContent({
    required String accountKey,
    required SystemLiveActivityDefinition definition,
    required LiveUpdateContent content,
    bool isDemo = false,
  }) {
    return LiveUpdateNotificationPackage(
      accountKey: accountKey,
      ownerGeneration: sha256.convert(utf8.encode(accountKey)).toString(),
      definitionId: definition.id,
      targetAppId: definition.targetAppId,
      render: content.render,
      boundaries: content.boundaries,
      isDemo: isDemo,
      postImmediately: content.postImmediately || isDemo,
      cancelExisting: content.cancelExisting,
    );
  }

  Map<String, dynamic> toJson({bool includeAccountKey = true}) => {
    if (includeAccountKey) 'accountKey': accountKey,
    if (ownerGeneration.isNotEmpty) 'ownerGeneration': ownerGeneration,
    'definitionId': definitionId,
    'targetAppId': targetAppId,
    'render': render.toJson(),
    'boundaries': [for (final boundary in boundaries) boundary.toJson()],
    'isDemo': isDemo,
    'postImmediately': postImmediately,
    'cancelExisting': cancelExisting,
  };

  factory LiveUpdateNotificationPackage.fromJson(Map<String, dynamic> json) {
    final rawBoundaries = json['boundaries'];
    return LiveUpdateNotificationPackage(
      accountKey: _string(json, 'accountKey'),
      ownerGeneration: _string(json, 'ownerGeneration'),
      definitionId: _string(json, 'definitionId'),
      targetAppId: _string(json, 'targetAppId'),
      render: LiveUpdateRender.fromJson(_map(json, 'render')),
      boundaries:
          rawBoundaries is List
              ? rawBoundaries
                  .whereType<Map<String, dynamic>>()
                  .map(LiveUpdateBoundaryRender.fromJson)
                  .toList(growable: false)
              : const [],
      isDemo: json['isDemo'] == true,
      postImmediately: json['postImmediately'] != false,
      cancelExisting: json['cancelExisting'] == true,
    );
  }
}

LiveUpdateRender _placeholderRender(String message) {
  return LiveUpdateRender(
    title: 'MyCHU 实时动态',
    body: message,
    progress: 0,
    progressMax: 0,
    requestPromoted: false,
    ongoing: false,
  );
}

String _string(Map<String, dynamic> json, String key) =>
    json[key] is String ? json[key] as String : '';

int _int(Map<String, dynamic> json, String key) {
  final value = json[key];
  return value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

DateTime _dateTime(Map<String, dynamic> json, String key) {
  final raw = json[key];
  return raw is String ? (DateTime.tryParse(raw) ?? east8Now()) : east8Now();
}

Map<String, dynamic> _map(Map<String, dynamic> json, String key) {
  final raw = json[key];
  return raw is Map<String, dynamic> ? raw : const {};
}
