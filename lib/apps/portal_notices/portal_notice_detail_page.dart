import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/user_error_message.dart';
import 'mobile_campus_notice_models.dart';
import 'mobile_campus_notice_rich_text.dart';
import 'mobile_campus_notice_service.dart';
import 'portal_notice_presentation.dart';
import 'package:mychu/widgets/apple_window_controls.dart';

typedef PortalNoticeDetailLoader =
    Future<MobileCampusNoticeDetail> Function(String messageId, String tagId);

class PortalNoticeDetailPage extends StatefulWidget {
  final String messageId;
  final String tagId;
  final String title;

  final PortalNoticeDetailLoader? loader;
  final bool embedded;
  final ValueChanged<MobileCampusNoticeDetail>? onLoaded;

  const PortalNoticeDetailPage({
    super.key,
    required this.messageId,
    required this.tagId,
    required this.title,

    this.loader,
    this.embedded = false,
    this.onLoaded,
  });

  @override
  State<PortalNoticeDetailPage> createState() => _PortalNoticeDetailPageState();
}

class _PortalNoticeDetailPageState extends State<PortalNoticeDetailPage> {
  final MobileCampusNoticeService _service = MobileCampusNoticeService();
  MobileCampusNoticeDetail? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final loader = widget.loader;
      final detail =
          loader == null
              ? await _service.fetchDetail(
                messageId: widget.messageId,
                tagId: widget.tagId,
              )
              : await loader(widget.messageId, widget.tagId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
      widget.onLoaded?.call(detail);
    } catch (error) {
      if (!mounted) return;
      logUserFacingError(UserErrorContext.network, error, operation: 'notice');
      setState(() {
        _error = userFacingError(UserErrorContext.network, error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _buildBody();
    return Scaffold(
      appBar: WindowControlsAwareAppBar(
        child: AppBar(title: const Text('公告详情')),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return PortalNoticeFullPageError(message: error, onRetry: _load);
    }
    final detail = _detail;
    if (detail == null) {
      return const Center(child: Text('公告正文加载失败'));
    }
    final detailTitle =
        detail.title.trim().isEmpty ? widget.title : detail.title;
    final metadata = [
      detail.department,
      detail.publishedAt,
    ].where((item) => item.isNotEmpty).join(' · ');
    final titleStyle = Theme.of(
      context,
    ).textTheme.titleLarge?.copyWith(height: 1.3);
    return SingleChildScrollView(
      key: const ValueKey('portal-notice-detail-scroll'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            detailTitle,
            key: const ValueKey('portal-notice-detail-title'),
            style: titleStyle,
          ),
          if (metadata.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              metadata,
              key: const ValueKey('portal-notice-detail-metadata'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (detail.contentHtml.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: Text('暂无正文')),
            )
          else
            MobileCampusNoticeRichText(
              html: detail.contentHtml,

              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.7,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
        ],
      ),
    );
  }
}
