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
5. The Supabase project URL and publishable key are compiled in
   (`lib/services/supabase/supabase_project_defaults.dart`), so Official Release needs
   no extra configuration. `-SupabaseUrl` / `-SupabasePublishableKey` (or the matching
   environment variables) only override the project for testing or key rotation.

Debug queries the official UL release stream (build 15 maps to Android code 2015).
The downloaded official APK installs as the official app; it does not replace Debug.
A missing configuration fails the supplied Debug/Official build commands. Preview
may omit it and use Fenfa. API/network failure still allows the existing Fenfa fallback.

UL credentials are embedded in the APK and can be extracted. Keep them out of Git
and logs, and keep upload/publish routes blocked at the public API origin.
Mapbox public token may be supplied by MAPBOX_PUBLIC_ACCESS_TOKEN (CLI) or included
in the local JSON under that key (IDE); the Mapbox downloads secret stays in the environment.

## Supabase

Since 1.3.0 the content backend defaults to Supabase. Copy `config/supabase.example.json`
to `.local/supabase.json` and pass
`--dart-define-from-file=.local/supabase.json` to Flutter, alongside the existing
UpgradeLink configuration. Both modules share `MYCHU_SUPABASE_URL` and
`MYCHU_SUPABASE_PUBLISHABLE_KEY`; legacy `MYCHU_SUPABASE_ANON_KEY` remains a fallback
only when the canonical key is absent. Never provide service_role or secret keys.

Announcements/feedback use Supabase since 1.3.0 whenever a project connection is present;
a build without connection settings uses Fenfa, so nothing changes until a project is
configured. There is no separate backend switch: drop the connection to roll back.
`MYCHU_ANNOUNCEMENT_FALLBACK` controls read fallback only. Feedback never switches
backends after an uncertain submission. Policies sync independently of the optional
remote-services preference, after agreement acceptance. Missing connection settings
prevent network requests but retain cached restrictions and high-risk fail-closed rules.
Both modules read the same connection file; do not maintain a second one. Deployment and consent prerequisites:
the private integration guide (`doc/integrations/supabase_integration.md`).

Agreement resources use the same project URL at the public `privacy-policies`
Storage bucket, without apikey or previous consent. `MYCHU_PRIVACY_BASE_URL` is an
optional legacy override. First use needs a complete validated agreement; historical
consent can continue offline, but only an explicit version 5+ receipt authorizes the
new Supabase business services. Publish resources only after completing the privacy
release checklist in the unified guide.

Public proposals, votes and comments are available to everyone who accepts version 5+
and keeps remote services on; there is no build switch. Supabase Anonymous Sign-Ins
must be enabled for participation. Setup steps are in the private community
guide (`doc/integrations/feedback_community.md`).

The local test configuration selects Supabase content, with Fenfa announcement fallback
retained. `tool/run_debug.ps1` loads the optional
`.local/supabase.json` after the UL file, or accepts `-SupabaseConfigFile`.
IDE has Supabase dual-track and Fenfa content rollback profiles; the latter keeps
the same project connection and overrides only the content backend. Official release
configuration is not automatically changed. Deployment and rollback steps are in the
private integration guide (`doc/integrations/supabase_integration.md`).
