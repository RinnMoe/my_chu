# Android build configuration

1. Copy `config/upgradelink.example.json` to `.local/upgradelink.json` and fill in
   the official UL application key and API AccessKey/SecretKey. `.local/` is ignored.
   Never put admin, storage or APK signing credentials in this file.
2. VS Code: choose **MyCHU Debug (UL release stream)**. Android Studio: choose
   the shared **MyCHU Debug** run configuration. Both pass the same JSON to Flutter.
3. CLI: run `pwsh -File <scripts-dir>/run_debug.ps1 -Device <id>` or
   `pwsh -File <scripts-dir>/build_android_release.ps1 -Channel official`.
   In the private source repo the equivalents are `tool/run_debug.ps1` and
   `tool/build_release.ps1`. Use `-UpgradeLinkConfigFile` to override the file path.
   Plain Flutter commands require `--dart-define-from-file=.local/upgradelink.json`.
4. GitHub Actions: set **MYCHU_UPGRADELINK_CONFIG_JSON** to the same JSON in the
   **android-release** environment. Existing signing and Mapbox secrets/variables
   are still required. A new release tag must include the updated workflow and source.

Debug queries the official UL release stream (build 14 maps to Android code 2014).
The downloaded official APK installs as the official app; it does not replace Debug.
A missing configuration fails the supplied Debug/Official build commands. Preview
may omit it and use Fenfa. API/network failure still allows the existing Fenfa fallback.

UL credentials are embedded in the APK and can be extracted. Keep them out of Git
and logs, and keep upload/publish routes blocked at the public API origin.
Mapbox public token may be supplied by MAPBOX_PUBLIC_ACCESS_TOKEN (CLI) or included
in the local JSON under that key (IDE); the Mapbox downloads secret stays in the environment.
