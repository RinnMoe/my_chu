/*
 * Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
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

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_ohos/src/messages.g.dart';
import 'package:url_launcher_ohos/url_launcher_ohos.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  late _FakeUrlLauncherApi api;

  setUp(() {
    api = _FakeUrlLauncherApi();
  });

  test('registers instance', () {
    UrlLauncherOhos.registerWith();
    expect(UrlLauncherPlatform.instance, isA<UrlLauncherOhos>());
  });

  group('canLaunch', () {
    test('returns true', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool canLaunch = await launcher.canLaunch('http://example.com/');

      expect(canLaunch, true);
    });

    test('returns false', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool canLaunch = await launcher.canLaunch('unknown://scheme');

      expect(canLaunch, false);
    });

    test('checks a generic URL if an http URL returns false', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool canLaunch = await launcher
          .canLaunch('http://${_FakeUrlLauncherApi.specialHandlerDomain}');

      expect(canLaunch, true);
    });

    test('checks a generic URL if an https URL returns false', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool canLaunch = await launcher
          .canLaunch('https://${_FakeUrlLauncherApi.specialHandlerDomain}');

      expect(canLaunch, true);
    });
  });

  group('legacy launch without webview', () {
    test('calls through', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launch(
        'http://example.com/',
        useSafariVC: true,
        useWebView: false,
        enableJavaScript: false,
        enableDomStorage: false,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );

      expect(launched, true);
      expect(api.usedWebView, false);
      expect(api.passedWebViewOptions?.headers, isEmpty);
    });

    test('passes headers', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launch(
        'http://example.com/',
        useSafariVC: true,
        useWebView: false,
        enableJavaScript: false,
        enableDomStorage: false,
        universalLinksOnly: false,
        headers: const <String, String>{'key': 'value'},
      );
      expect(api.passedWebViewOptions?.headers.length, 1);
      expect(api.passedWebViewOptions?.headers['key'], 'value');
    });

    test('passes through no-activity exception', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launch(
            'https://noactivity',
            useSafariVC: false,
            useWebView: false,
            enableJavaScript: false,
            enableDomStorage: false,
            universalLinksOnly: false,
            headers: const <String, String>{},
          ),
          throwsA(isA<PlatformException>()));
    });

    test('throws if there is no handling activity', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launch(
            'unknown://scheme',
            useSafariVC: false,
            useWebView: false,
            enableJavaScript: false,
            enableDomStorage: false,
            universalLinksOnly: false,
            headers: const <String, String>{},
          ),
          throwsA(isA<PlatformException>().having(
              (PlatformException e) => e.code, 'code', 'ACTIVITY_NOT_FOUND')));
    });
  });

  group('legacy launch with webview', () {
    test('calls through', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launch(
        'http://example.com/',
        useSafariVC: true,
        useWebView: true,
        enableJavaScript: false,
        enableDomStorage: false,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );
      expect(launched, true);
      expect(api.usedWebView, true);
      // expect(api.allowedCustomTab, false); // OHOS not supported
      expect(api.passedWebViewOptions?.enableDomStorage, false);
      expect(api.passedWebViewOptions?.enableJavaScript, false);
      expect(api.passedWebViewOptions?.headers, isEmpty);
    });

    test('passes enableJavaScript to webview', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launch(
        'http://example.com/',
        useSafariVC: true,
        useWebView: true,
        enableJavaScript: true,
        enableDomStorage: false,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );

      expect(api.passedWebViewOptions?.enableJavaScript, true);
    });

    test('passes enableDomStorage to webview', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launch(
        'http://example.com/',
        useSafariVC: true,
        useWebView: true,
        enableJavaScript: false,
        enableDomStorage: true,
        universalLinksOnly: false,
        headers: const <String, String>{},
      );

      expect(api.passedWebViewOptions?.enableDomStorage, true);
    });

    // OHOS not supported
    // test('passes showTitle to webview', () async {
    //   final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
    //   await launcher.launchUrl(
    //     'http://example.com/',
    //     const LaunchOptions(
    //       browserConfiguration: InAppBrowserConfiguration(
    //         showTitle: true,
    //       ),
    //     ),
    //   );

    //   expect(api.passedBrowserOptions?.showTitle, true);
    // });

    test('passes through no-activity exception', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launch(
            'https://noactivity',
            useSafariVC: false,
            useWebView: true,
            enableJavaScript: false,
            enableDomStorage: false,
            universalLinksOnly: false,
            headers: const <String, String>{},
          ),
          throwsA(isA<PlatformException>()));
    });

    test('throws if there is no handling activity', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launch(
            'unknown://scheme',
            useSafariVC: false,
            useWebView: true,
            enableJavaScript: false,
            enableDomStorage: false,
            universalLinksOnly: false,
            headers: const <String, String>{},
          ),
          throwsA(isA<PlatformException>().having(
              (PlatformException e) => e.code, 'code', 'ACTIVITY_NOT_FOUND')));
    });
  });

  group('launch without webview', () {
    test('calls through', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl(
        'http://example.com/',
        const LaunchOptions(mode: PreferredLaunchMode.externalApplication),
      );
      expect(launched, true);
      expect(api.usedWebView, false);
      expect(api.passedWebViewOptions?.headers, isEmpty);
    });

    test('passes headers', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launchUrl(
        'http://example.com/',
        const LaunchOptions(
            mode: PreferredLaunchMode.externalApplication,
            webViewConfiguration: InAppWebViewConfiguration(
                headers: <String, String>{'key': 'value'})),
      );
      expect(api.passedWebViewOptions?.headers.length, 1);
      expect(api.passedWebViewOptions?.headers['key'], 'value');
    });

    test('passes through no-activity exception', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launchUrl('https://noactivity', const LaunchOptions()),
          throwsA(isA<PlatformException>()));
    });

    test('throws if there is no handling activity', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launchUrl('unknown://scheme', const LaunchOptions()),
          throwsA(isA<PlatformException>().having(
              (PlatformException e) => e.code, 'code', 'ACTIVITY_NOT_FOUND')));
    });
  });

  group('launch with webview', () {
    test('calls through', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl('http://example.com/',
          const LaunchOptions(mode: PreferredLaunchMode.inAppWebView));
      expect(launched, true);
      expect(api.usedWebView, true);
      // expect(api.allowedCustomTab, false); // OHOS not supported
      expect(api.passedWebViewOptions?.enableDomStorage, true);
      expect(api.passedWebViewOptions?.enableJavaScript, true);
      expect(api.passedWebViewOptions?.headers, isEmpty);
    });

    test('passes enableJavaScript to webview', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launchUrl(
          'http://example.com/',
          const LaunchOptions(
              mode: PreferredLaunchMode.inAppWebView,
              webViewConfiguration:
                  InAppWebViewConfiguration(enableJavaScript: false)));

      expect(api.passedWebViewOptions?.enableJavaScript, false);
    });

    test('passes enableDomStorage to webview', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await launcher.launchUrl(
          'http://example.com/',
          const LaunchOptions(
              mode: PreferredLaunchMode.inAppWebView,
              webViewConfiguration:
                  InAppWebViewConfiguration(enableDomStorage: false)));

      expect(api.passedWebViewOptions?.enableDomStorage, false);
    });

    test('passes through no-activity exception', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launchUrl('https://noactivity',
              const LaunchOptions(mode: PreferredLaunchMode.inAppWebView)),
          throwsA(isA<PlatformException>()));
    });

    test('throws if there is no handling activity', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      await expectLater(
          launcher.launchUrl('unknown://scheme',
              const LaunchOptions(mode: PreferredLaunchMode.inAppWebView)),
          throwsA(isA<PlatformException>().having(
              (PlatformException e) => e.code, 'code', 'ACTIVITY_NOT_FOUND')));
    });
  });

  group('launch with custom tab', () {
    test('calls through', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl('http://example.com/',
          const LaunchOptions(mode: PreferredLaunchMode.inAppBrowserView));
      expect(launched, true);
      expect(api.usedWebView, true);
      // expect(api.allowedCustomTab, true); // OHOS not supported
    });
  });

  group('launch with platform default', () {
    test('uses custom tabs for http', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl(
          'http://example.com/', const LaunchOptions());
      expect(launched, true);
      expect(api.usedWebView, true);
      // expect(api.allowedCustomTab, true); // OHOS not supported
    });

    test('uses custom tabs for https', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl(
          'https://example.com/', const LaunchOptions());
      expect(launched, true);
      expect(api.usedWebView, true);
      // expect(api.allowedCustomTab, true); // OHOS not supported
    });

    test('uses external for other schemes', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      final bool launched = await launcher.launchUrl(
          'supportedcustomscheme://example.com/', const LaunchOptions());
      expect(launched, true);
      expect(api.usedWebView, false);
    });
  });

  group('supportsMode', () {
    test('returns true for platformDefault', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      expect(await launcher.supportsMode(PreferredLaunchMode.platformDefault),
          true);
    });

     // OHOS not supported,`UrlLauncherOhos`未重写`supportsMode()`，使用 `UrlLauncherPlatform` 的默认实现，仅对 `platformDefault` 返回 true，其他所有模式返回 fals
    test(skip: true, 'returns true for external application', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      expect(
          await launcher.supportsMode(PreferredLaunchMode.externalApplication),
          true);
    });

    // OHOS not supported,`UrlLauncherOhos`未重写`supportsMode()`，使用 `UrlLauncherPlatform` 的默认实现，仅对 `platformDefault` 返回 true，其他所有模式返回 fals
    test(skip: true, 'returns true for in app web view', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      expect(
          await launcher.supportsMode(PreferredLaunchMode.inAppWebView), true);
    });

    // OHOS not supported,`UrlLauncherOhos`未重写`supportsMode()`，使用 `UrlLauncherPlatform` 的默认实现，仅对 `platformDefault` 返回 true，其他所有模式返回 fals
    test(skip: true, 'returns true for in app browser view when available', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      // api.hasCustomTabSupport = true; // OHOS not supported
      expect(await launcher.supportsMode(PreferredLaunchMode.inAppBrowserView),
          true);
    });

    test('returns false for in app browser view when not available', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      // api.hasCustomTabSupport = false; // OHOS not supported
      expect(await launcher.supportsMode(PreferredLaunchMode.inAppBrowserView),
          false);
    });
  });

  group('supportsCloseForMode', () {
    test('returns true for in app web view', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      expect(
          await launcher.supportsCloseForMode(PreferredLaunchMode.inAppWebView),
          true);
    });

    test('returns false for other modes', () async {
      final UrlLauncherOhos launcher = UrlLauncherOhos(api: api);
      expect(
          await launcher
              .supportsCloseForMode(PreferredLaunchMode.externalApplication),
          false);
      expect(
          await launcher.supportsCloseForMode(
              PreferredLaunchMode.externalNonBrowserApplication),
          false);
      expect(
          await launcher
              .supportsCloseForMode(PreferredLaunchMode.inAppBrowserView),
          false);
    });
  });
}

/// A fake implementation of the host API that reacts to specific schemes.
///
/// See _launch for the behaviors.
class _FakeUrlLauncherApi implements UrlLauncherApi {
  // bool hasCustomTabSupport = true; // OHOS not supported
  WebViewOptions? passedWebViewOptions;
  // BrowserOptions? passedBrowserOptions; // OHOS not supported
  bool? usedWebView;
  // bool? allowedCustomTab; // OHOS not supported
  bool? closed;

  /// A domain that will be treated as having no handler, even for http(s).
  static String specialHandlerDomain = 'special.handler.domain';

  @override
  Future<bool> canLaunchUrl(String url) async {
    return _launch(url);
  }

  @override
  Future<bool> launchUrl(String url, Map<String?, String?> headers) async {
    passedWebViewOptions = WebViewOptions(
      enableJavaScript: false,
      enableDomStorage: false,
      headers: headers,
    );

    usedWebView = false;
    return _launch(url);
  }

  @override
  Future<void> closeWebView() async {
    closed = true;
  }

  @override
  Future<bool> openUrlInWebView(String url, WebViewOptions options) async {
    passedWebViewOptions = options;
    usedWebView = true;
    return _launch(url);
  }

  // OHOS not supported
  // @override
  // Future<bool> openUrlInApp(
  //   String url,
  //   bool allowCustomTab,
  //   WebViewOptions webViewOptions,
  //   BrowserOptions browserOptions,
  // ) async {
  //   passedWebViewOptions = webViewOptions;
  //   passedBrowserOptions = browserOptions;
  //   usedWebView = true;
  //   allowedCustomTab = allowCustomTab;
  //   return _launch(url);
  // }

  // OHOS not supported
  // @override
  // Future<bool> supportsCustomTabs() async {
  //   return hasCustomTabSupport;
  // }

  bool _launch(String url) {
    final String scheme = url.split(':')[0];
    switch (scheme) {
      case 'http':
      case 'https':
      case 'supportedcustomscheme':
        if (url.endsWith('noactivity')) {
          throw PlatformException(code: 'NO_ACTIVITY');
        }
        return !url.contains(specialHandlerDomain);
      default:
        return false;
    }
  }

  @override
  // ignore: non_constant_identifier_names
  BinaryMessenger? get pigeonVar_binaryMessenger => null;

  @override
  // ignore: non_constant_identifier_names
  String get pigeonVar_messageChannelSuffix => '';
}
