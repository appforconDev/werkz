// Build stamp (task 17 B) — every device report starts from a known build.
// Values are injected at build time via --dart-define; a build made without
// them says UNSTAMPED, which is itself the answer to "which build is this?".
// Use app/tool/device-run.sh so a device build is never unstamped.
const String werkzGitSha =
    String.fromEnvironment('WERKZ_GIT_SHA', defaultValue: 'unstamped');
const String werkzBuildNo =
    String.fromEnvironment('WERKZ_BUILD_NO', defaultValue: '0');

/// One-line stamp for corners and settings rows, e.g. "B412 · 124b24d".
const String werkzBuildStamp = 'B$werkzBuildNo · $werkzGitSha';
