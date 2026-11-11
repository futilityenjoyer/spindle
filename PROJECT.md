# Vinyl widget for Spotify: central project document

Working title: **Spindle** (placeholder; must not start with "Spot" per Spotify branding rules).
Last updated: 2026-11-12, M0 device testing.

## Status

| Phase | State |
|---|---|
| 1 Feasibility research | ✅ Done: [docs/FEASIBILITY.md](docs/FEASIBILITY.md) |
| 2 Architecture & planning | ✅ Done; owner decisions recorded below |
| 3 Core development | ✅ **M0 done** (2026-11-12). 🔨 **M1 written, not yet compiled or device-tested:** PKCE sign-in via the GitHub Pages return page, token file + cross-process refresh lock, currently-playing + queue fetch shared through the App Group; the widget shows the track and spins only while playing. |
| 4 Optimisation | Not started |
| 5 Testing | Not started |
| 6 Deployment docs | Install guide: [docs/INSTALL.md](docs/INSTALL.md) (iloader) |

## Current architecture (summary)

Full detail: [FEASIBILITY.md §4](docs/FEASIBILITY.md#4-recommended-architecture).

- **The widget is the product.** The companion app (SwiftUI) is a setup utility: connect Spotify, static widget preview, "Refresh widget now", settings and diagnostics. It makes one Web API fetch when opened. No in-app vinyl, and no Spotify iOS SDK.
- **Widget extension** (WidgetKit):
  - Spotify Web API `currently-playing` + `queue` in one burst per reload, skipped if the shared snapshot is < 60 s old.
  - The timeline predicts each upcoming track boundary from the queue, then stops at "last seen" after the next reload date.
  - Reloads about every 10 min while playing, plus unbudgeted refresh / play-pause intents.
  - Continuous spin via vendored ClockHandKit (private effect), with a static fallback.
- **Shared state:** App Group container: snapshot JSON, artwork LRU, event log, and the Spotify token in a protected, backup-excluded file.
- **Auth:** PKCE through `ASWebAuthenticationSession`, custom URL scheme, no client secret.
- **Build:** XcodeGen + GitHub Actions `macos-26` → entitlement-correct ad-hoc-signed `.ipa` → **iloader** "Import IPA" with a free Apple ID (weekly re-install by USB).
- **Deployment target:** iOS 26.0 (matches CI simulators); test on iOS 26.x and 27.x.

## Decision log

| Date | Decision | Reason |
|---|---|---|
| 2026-11-11 | No Live Activity in v1 | Without APNs push it goes stale on every track change; same 2 s animation cap as widgets |
| 2026-11-11 | No background execution of any kind | Battery constraint; App Review 2.5.4; Spotify asks App Remote to disconnect on background |
| 2026-11-11 | ~~Core Animation for in-app spin~~ (superseded by the next row) | — |
| 2026-11-11 | **Full-bleed label only** (no Inscribed / Still modes) | Sole user; accepted Spotify's "don't crop" policy risk |
| 2026-11-11 | **No MetricKit / battery-metrics screen**; battery is judged via Settings › Battery | Owner preference; keeps Diagnostics to a simple reload/request log |
| 2026-11-11 | **Widget buttons: play/pause + skip** (each tap force-refreshes the widget) | Fixes staleness for anything done from the widget; changes made elsewhere are still caught at the ~10 min reload |
| 2026-11-12 | **CI pinned to Xcode 26.6**; Xcode 27 preview build dropped | Device test: the 26.6 build spins on iOS 27.2 |
| 2026-11-12 | **Spotify redirect URI: `https://futilityenjoyer.github.io/spindle/callback/`** (GitHub Pages page [docs/callback/index.html](docs/callback/index.html) forwards to `dev.spindlevinyl.auth://callback`) | Spotify's redirect-URI rules allow only HTTPS or loopback for apps created after 9 Apr 2025; custom schemes aren't listed. PKCE makes the forwarded code useless to others. |
| 2026-11-12 | **Install tool: iloader** "Import IPA" (replaces SideStore and Sideloadly) | Device test 3: iloader signs in and registers an App Group. SideStore in-app sign-in fails with -80045 (open upstream bug #1709). Trade-off: weekly re-install by USB from the PC. Retry SideStore once fixed, for on-device refresh. |
| 2026-11-12 | ~~Install tool: SideStore~~ (superseded by the row above) | Sideloadly grants no App Group on free accounts (device test 2). SideStore documents App Group support and refreshes on the phone. |
| 2026-11-12 | **Widget speed: 16⅔ RPM** (3.6 s per turn) | Owner compared 16⅔ vs 33⅓ side by side on the device and preferred the slower one |
| 2026-11-11 | **Token storage: protected App Group file** (not Keychain) | Can't break on weekly re-signing. Excluded from backup; readable only by app + widget. |
| 2026-11-11 | **Widget sizes: Small + Medium**, as in the prototype | Owner choice. Small = record + play/pause; Medium = record + track/artist + play/pause + skip |
| 2026-11-11 | **Widget-only scope:** the app is a setup utility; App Remote / Spotify iOS SDK dropped | Owner only wants the widget. Removes the least testable dependency (App Remote can't run on the CI simulator), the in-app animation engine and the reconnect/polling logic. A player screen can be added later without rework. |
| 2026-11-11 | ClockHandKit (source) over octree ClockHandRotationKit (binary) | octree path neutered on iOS 26.1+ SDK builds; ClockHandKit works on 26.1+/27 |
| 2026-11-11 | XcodeGen over Tuist | Simple YAML, no Xcode needed, easy to generate on CI |
| 2026-11-11 | Widget timeline = queue prediction + "last seen" bound (replaces rev 1's `trackEnd + 20 s` stop) | QA B1: rev 1 stopped the disc about half the time during normal listening. `GET /me/player/queue` confirmed available in Development Mode (Feb-2026 changelog) |

## Owner decisions (answered 2026-11-11)

| Decision | Answer | Consequence |
|---|---|---|
| Spotify Premium | **Yes**, the owner has Premium | Unblocks Development Mode; owner allowlists themselves in the dashboard (M1) |
| Signing path | **Free Apple ID** | SideStore primary, Sideloadly backup; 7-day re-sign; expiry banner/badge required |
| Default label style | **Full-bleed circle** (owner accepted the Spotify "don't crop" policy risk; worst case is Client ID revocation) | Default = circle-cropped art; Inscribed and Still label remain selectable in Settings |
| Repo visibility | **Public** GitHub repo | Unlimited free macOS CI; no secrets in repo (PKCE, Client ID only) |

Still to confirm at M0: the iPhone's iOS version (deployment target is 26.0).

## Completed features

**M0 (code written 2026-11-11; not yet built or device-tested):**

| Piece | Location |
|---|---|
| XcodeGen manifest (app + widget extension + App Group, ClockHandKit via SPM) | [project.yml](project.yml) |
| `Core` package: provisioning-profile parser, App Group resolver, widget heartbeat log, with unit tests | [Packages/Core](Packages/Core) |
| Runtime App Group discovery + shared file store | [Shared/](Shared) |
| "Spin test" widget (small 16⅔ RPM; medium 16⅔ vs 33⅓ side by side) | [Widget/](Widget) |
| Diagnostics app: App Group status, widget heartbeats, signature expiry, Xcode/SDK, effect probe | [App/](App) |
| CI: Core tests, then IPA built with **both** Xcode 26.6 and Xcode 27 (preview image) | [.github/workflows/ios.yml](.github/workflows/ios.yml) |
| Ad-hoc signing with entitlements + verification + IPA packaging | [scripts/make-ipa.sh](scripts/make-ipa.sh) |
| Windows → iPhone install guide for the spin test | [docs/INSTALL.md](docs/INSTALL.md) |

**Deferred from M0:** rendered PNG previews of widgets on CI move to M2, once the real vinyl renderer exists.

The design prototype is at [design/vinyl-prototype.html](design/vinyl-prototype.html).

## Outstanding tasks

See the roadmap in [FEASIBILITY.md §9](docs/FEASIBILITY.md#9-implementation-roadmap) (M0–M6).

## Known limitations

See [FEASIBILITY.md §7](docs/FEASIBILITY.md#7-compromises-explicit-not-hidden).

## Build instructions

See [docs/INSTALL.md](docs/INSTALL.md). In short: push to GitHub → the Actions "ios" workflow builds the IPAs → download the artifact → install with iloader using your free Apple ID. Pipeline research: [06-build-infrastructure.md](docs/research/06-build-infrastructure.md).

- **Bundle ID:** `dev.spindlevinyl.app`, widget `dev.spindlevinyl.app.widget`.
- **App Group:** `group.dev.spindlevinyl.shared`.
- Don't change these: each new bundle ID uses free-account App IDs (10 per week).

## Testing results

### M0 device test 1 (2026-11-12): iPhone, iOS 27.2 (24B119), Sideloadly, free Apple ID

| Check | Result |
|---|---|
| CI build (Xcode 26.6, SDK iphoneos26.5) | ✅ Compiled, installed |
| **Widget spins continuously** (ClockHandKit) | ✅ **Yes**. The key risk is retired for this toolchain/iOS pair. Preferred speed: 16⅔ RPM. |
| Widget appears in the gallery | ✅ Without trouble |
| Bundle ID after re-sign | `dev.spindlevinyl.app.4K99FM682B` (Sideloadly appends the team ID, like AltStore/SideStore) |
| Signature expiry shown | ✅ 7 days |
| App Group resolved | ❌ **Not found**; shared folder unavailable; therefore no widget heartbeat |

### M0 device test 2 (2026-11-12): same phone, build 2 with profile diagnostics

| Check | Result |
|---|---|
| Groups in embedded profile | **none** |
| ALTAppGroups | none |
| Profile name | "iOS Team Provisioning Profile: dev.spindlevinyl.app.4K99FM682B" |

**Conclusion:** Sideloadly (free Apple ID) does not enable the App Groups capability, even though the IPA's ad-hoc signature carries the entitlement (verified in CI). This isn't a resolver bug. The fix is to sideload with a tool that documents App Group support (SideStore / AltStore), or to use the paid program.

### M0 device test 3 (2026-11-12): iloader "Import IPA"

| Check | Result |
|---|---|
| SideStore (attempted first) | ❌ In-app Apple ID sign-in fails with **-80045** (known open SideStore bug, [#1709](https://github.com/SideStore/SideStore/issues/1709)); community anisette workaround didn't help |
| iloader sign-in + install | ✅ |
| Groups in profile | `group.dev.spindlevinyl.app.4K99FM682B` (iloader names the group after the bundle ID) |
| Resolved ID / Shared folder | ✅ Same value / OK. Found via the resolver's last-resort rule; unit test added |
| Widget heartbeat | ✅ Shown in the app after re-adding the widget. The widget writes to the shared folder, so both sides of the App Group work. |

The 12-scenario matrix will live here from M3 onward.
