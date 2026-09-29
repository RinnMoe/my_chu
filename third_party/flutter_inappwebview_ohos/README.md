# flutter_inappwebview_ohos

OpenHarmony platform implementation for [flutter_inappwebview](https://pub.dev/packages/flutter_inappwebview).

This package provides the native ArkTS plugin and Dart platform bindings used when building for OpenHarmony. Application code should depend on the main `flutter_inappwebview` package; this package is pulled in automatically as a federated plugin dependency.

## Documentation

For installation, compatibility, permissions, usage examples, and the full API reference, see the repository root documentation:

- [README.OpenHarmony_CN.md](../README.OpenHarmony_CN.md) (Chinese)
- [README.OpenHarmony.md](../README.OpenHarmony.md) (English)
- [CHANGELOG.OpenHarmony.md](../CHANGELOG.OpenHarmony.md)

## Package Layout

```text
lib/                          # Dart platform implementation (OhosInAppWebViewPlatform)
ohos/src/main/ets/            # ArkTS native plugin (InAppWebViewFlutterPlugin)
  components/plugin/
    webview/                  # InAppWebView, HeadlessInAppWebView, WebMessage
    in_app_browser/           # InAppBrowser
    content_blocker/          # ContentBlocker
    credential_database/      # HttpAuthCredentialDatabase
    print_job/                # PrintJobController
    pull_to_refresh/          # PullToRefreshController
    proxy/                    # ProxyController
```

## Known Issues (OpenHarmony)

- A blank page may appear when loading an abnormal or unreachable website.
- Map navigation links (`maps:` / external map apps) are not supported.

For more tracked issues, see [Known Issues](../README.OpenHarmony.md#known-issues) in the root README.

## License

Apache License 2.0. See the [LICENSE](../LICENSE) file in the repository root.
