import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../capabilities/authenticated_web_view_capability.dart';
import '../../capabilities/web_view_error_view.dart';
import '../../services/service_endpoints.dart';

class ExperimentCourseSelectionPage extends StatefulWidget {
  const ExperimentCourseSelectionPage({super.key});

  @override
  State<ExperimentCourseSelectionPage> createState() =>
      _ExperimentCourseSelectionPageState();
}

class _ExperimentCourseSelectionPageState
    extends State<ExperimentCourseSelectionPage> {
  late Future<UnmodifiableListView<UserScript>> _scripts = _loadScripts();

  Future<UnmodifiableListView<UserScript>> _loadScripts() async {
    // Bundled verbatim from CHUSYXKhelper 2.0.0. Keep its mobile synchronous
    // list/submission safeguards when updating the asset.
    final source = await rootBundle.loadString(
      'assets/experiment_course_selection/CHUSYXKhelper.user.js',
    );
    return UnmodifiableListView([
      UserScript(
        source: '''
(() => {
  if (location.protocol !== 'http:' ||
      location.hostname !== 'chdsyxk.chd.edu.cn' ||
      location.port !== '8088' ||
      !location.pathname.toLowerCase().startsWith('/apk/')) return;
  $source
})();
''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
        forMainFrameOnly: false,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UnmodifiableListView<UserScript>>(
      future: _scripts,
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          return AuthenticatedWebViewCapability.pageForService(
            title: '实验选课',
            url:
                CampusServiceEndpoints.experimentCourseSelectionSignInUri
                    .toString(),
            serviceId: CampusServices.experimentCourseSelection,
            initialUserScripts: snapshot.requireData,
          );
        }
        return Scaffold(
          appBar: AppBar(title: const Text('实验选课')),
          body:
              snapshot.hasError
                  ? WebViewErrorView(
                    message: '选课助手加载失败，请重试。',
                    onRetry: () => setState(() => _scripts = _loadScripts()),
                  )
                  : const Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
