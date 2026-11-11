# 05 — Battery & Performance (Phase 1 research)

**Agent:** 5, Battery & Performance Specialist
**Date:** 2026-11-11
**Scope:** Research only, no code. This covers the widget (WidgetKit), the companion SwiftUI app, and an optional Live Activity that shows the current Spotify track as a spinning vinyl.
**Evidence labels:**
- **VERIFIED** means confirmed this session against the cited source (Apple docs, a WWDC page, or a peer-reviewed paper).
- **INFERRED** means reasoned from verified facts or from consistent community reports. Treat it as a hypothesis and test it.
- **UNVERIFIED** means no authoritative source was found. Do not rely on it until it is measured.

> **No parity claim.** This document does not claim that our app will match or beat MD Vinyl's battery use. Section 6 says how to measure that comparison and where the measurement falls short.

> **Platform note (VERIFIED, needs a team decision):** The brief says iOS 26. Apple's docs, however, already describe **iOS 27** APIs, and WWDC26 (June 2026) announced iOS 27. For example, MetricKit's `MetricManager` is listed as "iOS 27 and later", and the old `MXMetricManager` page carries a deprecation notice ([MetricKit](https://developer.apple.com/documentation/metrickit), [WWDC26 session 222 "Meet the new MetricKit"](https://developer.apple.com/videos/play/wwdc2026/222/)). On 2026-11-11 the test device is probably on iOS 27. Plan for an iOS 26 deployment target and use iOS 27 APIs where they exist.

---

## 0. Executive summary

1. **The network is the biggest energy cost we control, and WidgetKit already rations it.** Each widget gets **40–70 reloads per day**, which works out to roughly every **15–60 minutes**. Reloads less than **~5 minutes** apart are not honoured (VERIFIED, [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)). So a widget that reloads when each track ends cannot follow every track change in the background. That limit is about freshness, not battery: the budget keeps our request rate low on its own.
2. **App-triggered reloads are budget-free while our app is in the foreground. Reloads from interactive widget buttons are also budget-free** (VERIFIED, same page). The cheapest accurate design is therefore a hybrid:
   - App Remote events while the app is in the foreground: no Web API calls, and reloads are free.
   - A `.after(trackEnd)` timeline with a 5-minute floor and adaptive back-off in the background.
   - A tap-to-refresh button that does not use the budget.
3. **Never try to earn the "active audio session" or "Now Playing" exemptions.** Playing silent audio, using location, or other keep-alive tricks would turn a near-zero background cost into a continuous one. They could also take audio focus away from Spotify.
4. **Images:** fetch the **300 px** Spotify image **once per album**. Downsample it with ImageIO to the exact pixel size needed, then store a pre-composited disc in the App Group under a size-bounded LRU. This keeps widget-extension peak memory far below the **~30 MB** jetsam limit. That limit is reported widely in Apple forums but is not in Apple's docs.
5. **Animation:**
   - **Widget.** Rotation with `_clockHandRotationEffect` is (INFERRED) a Core Animation animation run by the system's render process. Our extension does not wake for each frame, but the GPU and display still pay to render it.
   - **In-app.** Use one `CABasicAnimation` on a single pre-composited layer, capped at 30–60 fps through `preferredFrameRateRange`. Pause it whenever the app is not active and in front.
6. **Measurement without a Mac:** use Settings › Battery, MetricKit (`MetricManager` on iOS 27, `MXMetricManager` on iOS 26), and our own request and reload counters, shown on an in-app **Diagnostics** screen. Run an A/B/baseline protocol on alternating days. Apple's on-device **Power Profiler** can record a trace on iOS 26+, but analysing it needs Instruments on a borrowed or rented Mac.

---

## 1. Widget refresh strategy and energy

### 1.1 Verified platform facts

All quotes in this list are VERIFIED from [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date).

- *"For a widget the user frequently views, a daily budget typically includes from 40 to 70 refreshes. This rate roughly translates to widget reloads every 15 to 60 minutes."*
- The budget covers a rolling 24-hour window tuned to the user's habits. During the first few days the widget may get more reloads while the system learns.
- *"WidgetKit imposes a minimum amount of time before it reloads a widget. Your timeline provider should create timeline entries that are at least about 5 minutes apart."* WidgetKit may also coalesce reloads across widgets.
- Reloads that **do not count** against the budget:
  - the containing app is in the foreground
  - the containing app has an active audio or navigation session
  - the containing app is the current **Now Playing** app (`MPNowPlayingInfoCenter`)
  - the widget performs an **App Intent**, such as a button tap
  - the widget performs an animation
  - locale, Dynamic Type, or accessibility settings change
- Widgets on Home Screen pages the user rarely visits may get fewer reloads, and *"WidgetKit may reload the widget when it becomes visible"*. StandBy refreshes at a system rate that does not use the budget.
- Apple's own energy guidance: *"Reloading widgets consumes system resources and causes battery drain due to additional networking and processing... limit the frequency and number of updates you request to what's necessary."*
- The page does **not** say whether Low Power Mode changes the budget. See §5.
- Since iOS 26, widgets can also receive **WidgetKit push notifications**, which are budgeted and delivered opportunistically (VERIFIED, [Updating widgets with WidgetKit push notifications](https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications), [WWDC25 "What's new in widgets"](https://developer.apple.com/videos/play/wwdc2025/278/)). They need our own server polling Spotify, which is out of scope for a free personal app with no backend. Listed only so the option is known.

**Spotify side** (VERIFIED, [Spotify Web API rate limits](https://developer.spotify.com/documentation/web-api/concepts/rate-limits)): rate limits use a **rolling 30-second window**, a 429 response comes with `Retry-After` in seconds, and development-mode apps get a lower limit. A personal widget making a dozen calls per hour is far below any plausible limit.

### 1.2 Why the cost of a request is mostly radio "tail"

- **VERIFIED (Apple):** radios *"remain up for the duration of the activity and for an additional period of time in anticipation of more work. Sporadic network transactions result in high overhead"*, and *"Cellular network activity requires significantly more energy than activity over Wi-Fi"* ([Energy Efficiency Guide for iOS Apps – Energy and Networking](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/EnergyandNetworking.html)).
- **VERIFIED (academic, older hardware):** Huang et al., MobiSys 2012, measured an LTE RRC tail of **~11.6 s at ~1.06 W**. That is about **11–12 J per isolated request, whatever the payload size**, and LTE was up to 23× less power-efficient than Wi-Fi for small transfers ([paper PDF](https://www.cs.sjtu.edu.cn/~xue-gt/wireless/Paper/Energy%20efficiency%20of%20cellular%20network%20and%20smartphone/A%20Close%20Examination%20of%20Performance%20and%20Power.pdf)). 5G NR has its own RRC timers ([Narayanan et al., SIGCOMM 2021](https://www-users.cse.umn.edu/~fengqian/paper/5g_sigcomm21.pdf)). This session did not pull a 5G tail figure, so it is UNVERIFIED.
- **INFERRED order of magnitude:** a ~13 Wh iPhone battery holds about 47 kJ, so one isolated LTE request is roughly **0.02–0.03 % of battery**. Twelve requests per hour on cellular comes to about **0.3 %/h**; three per hour is about 0.07 %/h. Modern Apple modems with C-DRX and fast dormancy probably do better than 2012 Android hardware, so treat these as an upper bound.
- **Practical rule:** the number of separate radio wake-ups matters far more than bytes transferred. **Bundle** every network call a reload needs (token refresh, currently-playing, album image) into one burst a few seconds long, so they share a single tail.

### 1.3 The four strategies compared

Assumptions: average track about 3.5 min, so about 17 track changes per hour. "Requests" means Spotify Web API calls made by our code. Spotify's own audio streaming is excluded; we do not control it.

| Strategy | Requests per listening hour | Budget impact | Freshness | Energy verdict |
|---|---|---|---|---|
| **(a) Fixed interval**, e.g. `.after(now+15 min)` | 4 currently-playing, plus about 1 token refresh, plus images for new albums. Averaged over a day, the budget caps it at about 2–3/h. | Spends budget **even when nothing is playing** unless it backs off. 96 reloads/day at 15 min is more than the 40–70 budget, so the system throttles it anyway. | Poor: shows the wrong song for up to 15+ min | **Worst per useful update.** Acceptable only as a slow fallback (≥ 60 min) when idle. |
| **(b) Reload at track end**: `.after(now + (duration_ms − progress_ms) + grace)` | Wants about 17/h. The ≥5-min floor caps it at **≤ 12/h**, and the daily budget caps total use at 40–70. About 3 h of listening uses up a day's budget. | Uses budget only around real track changes. Needs back-off when paused or idle (see §1.4). | Good for long tracks. Lags on skips and short tracks. Cannot see pause or skip until the next reload. | **Best background option.** Each reload is matched to a likely state change. |
| **(c) App-triggered** `WidgetCenter.shared.reloadTimelines(ofKind:)` on App Remote `playerStateDidChange` while foreground | **0 Web API calls.** App Remote is IPC to the Spotify app, and art comes from `fetchImage` or our cache. | **Free.** Foreground reloads are exempt (VERIFIED). | Real-time while the app is open | **Cheapest and most accurate**, but only while the app is foreground. Debounce to ≤ 1 reload per 2 s so rapid skipping does not cause repeated renders. |
| **(d) Interactive refresh button** (`Button(intent:)` → App Intent → reload) | 1 per tap | **Free.** App Intent reloads are exempt (VERIFIED). | On demand | **Very cheap**, because it is user-driven. Should be the main way to correct a stale widget. Rate-limit to one network call per 10 s so mashing the button does nothing extra. |

**Recommended combination (INFERRED, measure it):** (c) whenever the app is in the foreground; (b) as the background timeline, with back-off; (d) always available; (a) only as an idle fallback.

**Expected background request rate:**
- While listening with the widget visible and the app closed: **≤ 12 currently-playing + ≤ 1 token + new-album images**, in practice ≤ ~15 requests/h.
- Averaged over a day of heavy listening: **~2–4 requests/h**, because the budget caps it.
- Idle (nothing playing): **≤ 1 request/h**, ideally 0 (§1.4).

### 1.4 Timeline design rules (INFERRED from verified constraints)

- **Playing** (`is_playing == true`):
  - Entry 1 at `now`: spinning disc, plus `ProgressView(timerInterval: start...end)`. Track progress then advances without reloads (VERIFIED, [Displaying dynamic dates](https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates)).
  - Policy: `.after(max(trackEnd + 3 s, now + 5 min))`.
  - Entry 2 at `trackEnd + 10 min`: a **static, "stale" disc with no rotation**. If the system postpones the next reload, the widget stops spinning by itself instead of spinning on stale data for hours. This also bounds render cost (§3).
- **Paused, or HTTP 204 (nothing playing):** static disc. Policy `.after(now + 60 min)`, or `.never` once paused for more than 2 h, relying on the app and the button (b, c, d) to wake it.
- **Errors (offline, 401 that cannot be refreshed, 429):** keep the last cached entry, show it as stale, and use `.after(now + 30 min)`, or `Retry-After` if that is longer. **Never retry in a tight loop from the extension.**
- **Low Power Mode:** see §5.

Implementation notes:
- Request only what is needed: `GET /v1/me/player/currently-playing?market=from_token`. The `market` parameter drops `available_markets` arrays, which shrinks the payload (INFERRED from Spotify API behaviour; verify the response size).
- Do the token refresh in the **same burst**, and only when the token has expired or is within 5 min of expiring.
- Set `timeoutIntervalForRequest` to about 8 s. Apple says a widget request *"may not have enough time to complete before the system halts the widget extension"* (VERIFIED, [Making network requests in a widget extension](https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension)). Background `URLSession` with `onBackgroundURLSessionEvents` is unnecessary for a ~2–5 KB JSON call. Use it only if image downloads time out in testing.
- **Write state to the App Group** (track ID, album ID, `progress_ms`, `duration_ms`, `fetchedAt`, `is_playing`) from both the app (via App Remote) and the extension. Before any network call, the extension should check whether a record **from the last 60 s** already exists, for example one the app just wrote. If so, it should skip the call.

---

## 2. Image pipeline

### 2.1 Verified and reported constraints

- **Widget extension memory:** many Apple Developer Forums crash logs show `EXC_RESOURCE RESOURCE_TYPE_MEMORY (limit=30 MB)` ([thread 713561](https://developer.apple.com/forums/thread/713561), [733347](https://developer.apple.com/forums/thread/733347), [842805](https://developer.apple.com/forums/thread/842805)). The number appears in Apple's own crash reports but **not in Apple's documentation**, so it is **VERIFIED-as-observed, not documented**. Forum users say one budget is shared across all of an extension's widget kinds and sizes ([thread 795793](https://developer.apple.com/forums/thread/795793), no Apple reply), which is UNVERIFIED. An Apple engineer reply also asks that the **archived timeline stay under 30 MB** ([thread 778731](https://developer.apple.com/forums/thread/778731)).
- **Per-image pixel-area limit:** WidgetKit logs *"Widget archival failed due to image being too large"*, with maximum areas of about **718,080 px** (≈ 847×847) on some devices, and larger on others ([thread 773785](https://developer.apple.com/forums/thread/773785), [thread 710745](https://developer.apple.com/forums/thread/710745)). This is VERIFIED-as-observed. The value depends on device and family and is not documented.
- **Live Activities:** image assets must be *"smaller or equal to the size of the presentation"*, otherwise the activity *"might fail to start"*. Static plus dynamic ActivityKit data must be ≤ **4 KB**. *"A Live Activity can't access the network"* (VERIFIED, [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)).
- **Downsampling:** WWDC18 session 219, "Image and Graphics Best Practices" ([video](https://developer.apple.com/videos/play/wwdc2018/219/), [notes](https://wwdcnotes.com/documentation/wwdc18-219-image-and-graphics-best-practices/)), recommends `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize`, `kCGImageSourceCreateThumbnailFromImageAlways`, and `kCGImageSourceCreateThumbnailWithTransform`, with `kCGImageSourceShouldCache: false` on the source. Decoded memory is about width × height × 4 bytes, set by the **pixel** size, not the file size ([ImageIO `CGImageSourceCreateThumbnailAtIndex`](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:))). The session and these option names are VERIFIED. The exact caching behaviour of `kCGImageSourceShouldCacheImmediately` is INFERRED.
- **AsyncImage:** WidgetKit renders a snapshot and *"ignores other views"* not on its supported list ([Creating a widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension)). Community reports agree that `AsyncImage` never loads in widgets, because there is no live view to update. That point is INFERRED, but it is consistent across reports. **Rule:** fetch image data inside `getTimeline`/`timeline(for:in:)` (or read it from the cache) and pass a ready `UIImage` in the entry.

### 2.2 Recommended pipeline

1. **Source:** Spotify returns several sizes per album, commonly 640, 300, and 64 px (INFERRED; check the `images` array). Use the **300 px** image (~20–50 KB JPEG) for the disc label. Use 640 px only if a design shows art across the **whole** disc in the large or extra-large widget. Since iOS 27 there is an **extra-large 4×6 widget** ([9to5Mac](https://9to5mac.com/2026/06/08/ios-27-adds-extra-large-widgets-for-your-extra-large-needs/)). Do not support it until memory is measured.
2. **Fetch once per album.** Key the cache on `album.id`, not on track ID or image URL. Download in the **same radio burst** as the currently-playing call. While the app is in the foreground, prefer App Remote's `fetchImage(forItem:withSize:)` (IPC, no network) at exactly the size needed.
3. **Downsample at decode time** with ImageIO to the **target pixel size**: label diameter in points × `displayScale`. For example, an 80 pt label at 3× is 240 px. Never decode at full size and then scale in SwiftUI.
4. **Pre-composite (recommended):** render the vinyl disc (grooves, sheen, label mask, art) into **one** bitmap with alpha at the exact pixel size for each widget family. The rotating view is then one opaque-edged image, with no live masks, blurs, or shadows. Keep any shadow in a **static** layer underneath. INFERRED benefit: cheaper render-server compositing per frame and fewer offscreen passes. Do the compositing **in the app** where possible (when App Remote reports a new album), so the extension usually just loads a finished file.
5. **Storage:** App Group container `Library/Caches/Art/`.
   - Raw: `<albumId>-300.jpg`, the original bytes, **not re-encoded** (no quality loss, no encode CPU).
   - Composites: `<albumId>-<family>-<scale>.png`, PNG because we need alpha.
   - HEIC with alpha is about 2× smaller, but encoding costs more CPU and support for writing alpha is less certain (INFERRED). At these sizes (≤ ~300 KB per composite) file size does not matter, so prefer PNG for simplicity and decode predictability. JPEG has no alpha, so it suits only the raw square art.
6. **LRU:** cap at about **100 albums or 25 MB**, whichever comes first. Track last-access time in a small JSON index. Evict when writing. Remember that `Caches` may be purged by the OS (INFERRED), so a cache miss must always fall back to a fetch.
7. **Decode cost:** a 300×300 JPEG decodes to 360 KB and a 450×450 RGBA composite to 810 KB. Both take well under 10 ms on A-series chips (INFERRED). Peak extension memory should stay at **≤ 15 MB**, half the observed limit (§7).

---

## 3. Animation energy

### 3.1 Widget: `_clockHandRotationEffect`

- **What is known (VERIFIED-as-reported, not Apple-documented):** it is a **private, underscored SwiftUI modifier** that gives continuous rotation in widgets with periods like `.secondHand` or a custom duration. It is used by community packages such as [ClockHandRotationKit](https://github.com/octree/ClockHandRotationKit), and see the [Scripting app guide](https://scriptingapp.github.io/guide/Widget/Animation%20for%20Widget%20and%20LiveActivity). An Apple engineer, quoted in community threads, said public widget APIs cannot animate arbitrary content over time apart from date text. Being private, it can break or vanish in any iOS release. For a sideloaded personal app App Store rejection does not matter, but **fragility** does.
- **Cost model (INFERRED):** Apple's Clock widget second hand works the same way. The rotation is defined once in the archived view and executed as a time-based Core Animation animation by the system's rendering pipeline (SpringBoard / render server). **Our extension does not run per frame.** Its CPU cost is zero between reloads. The real costs are:
  - the render server compositing one rotating layer each frame while the widget is **on screen**
  - possibly keeping the display at a higher refresh rate. WWDC22 says the screen's refresh rate is driven by the highest-rate animation visible ([WWDC22 "Power down: Improve battery consumption"](https://developer.apple.com/videos/play/wwdc2022/10083/)). Whether the system caps widget rotation at a low rate is UNVERIFIED.
- **Paused when not visible? (INFERRED, high confidence):** Core Animation does not render layers that are off screen. When the Home Screen page is not shown, an app covers it, or the display is off, there are no frames and no GPU cost. On Always-On displays, Apple says Live Activities *"doesn't perform animations to preserve battery life in Always On"* (VERIFIED for Live Activities, [ActivityKit doc](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)). Widgets probably behave the same way (INFERRED).
- **Budget:** *"The widget performs an animation"* is on Apple's list of things that do not count against the budget (VERIFIED). That refers to public entry-transition animations. Whether the continuous private rotation interacts with the budget at all is UNVERIFIED, though community use suggests it does not.
- **Rules:**
  - Rotate **one pre-composited image**.
  - Use 33⅓ rpm, a 1.8 s period. The rate is cosmetic; the rotation speed barely matters to energy (INFERRED).
  - **Stop the rotation** (render a static entry) when paused or stale. §1.4 has the stale-entry trick.
  - Make spinning a **user setting**, including "spin only when charging / not in Low Power Mode".
  - Keep a **public fallback** (static disc plus `ProgressView(timerInterval:)`) behind a feature flag in case the private API breaks.

### 3.2 In-app spinning disc

| Technique | Where per-frame work runs | Energy (INFERRED unless marked) |
|---|---|---|
| **`CABasicAnimation`** on `transform.rotation.z`, `repeatCount = .infinity`, `byValue = 2π` | Render server only. The app's main thread is idle. | **Lowest.** One layer, one texture rotated by the GPU. **Preferred.** |
| SwiftUI `.rotationEffect` + `.animation(.linear.repeatForever)` | SwiftUI usually drives the interpolation in-process each frame | Low to moderate. Measure it. Wrap a `UIView` with `CABasicAnimation` via `UIViewRepresentable` if CPU shows up. |
| `TimelineView(.animation)` or `CADisplayLink` that sets the angle every frame | **App main thread every frame**, plus a SwiftUI body re-evaluation | **Highest.** Avoid it, except as a stepped low-fps effect. |

- **Frame rate (VERIFIED):** iPhone apps run at **≤ 60 Hz unless `CADisableMinimumFrameDurationOnPhone` = true**. `CAAnimation` and `CADisplayLink` accept `preferredFrameRateRange` (iOS 15+). Apple says *"smaller movements — like an icon that rotates in-place — may look just fine at a lower rate. To save energy, choose the lowest frame rate that achieves your desired visual flow"*, and *"the system disables faster refresh rates in low power mode or if a device gets hot"* ([Optimizing iPhone and iPad apps to support ProMotion displays](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays), [`CADisplayLink.preferredFrameRateRange`](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)). WWDC22 cites up to **20 %** less battery drain from moving a secondary animation from 60 to 30 fps (VERIFIED, session 10083).
- **Recommendation:**
  - **Do not** add `CADisableMinimumFrameDurationOnPhone`.
  - Set `CAFrameRateRange(minimum: 24, maximum: 60, preferred: 60)` normally, and `(15, 30, 30)` in Low Power Mode or at `thermalState ≥ .fair`.
  - At 33⅓ rpm (200°/s), 30 fps means 6.7° per frame. A plain disc should still look smooth, but label text may show judder, so test both.
- **Stop when not visible:**
  - Pause on `scenePhase != .active` and on `onDisappear` using the `layer.speed = 0` / `timeOffset` pattern, so the angle is kept.
  - Resume on `.active`.
  - Also pause when the track is paused.
  - Core Animation removes or freezes animations in the background anyway, but explicit control avoids "rollback" glitches ([forum thread 742776](https://developer.apple.com/forums/thread/742776)).
- **Dark UI:** on OLED displays, dark interfaces use much less display power. WWDC22 cites up to 70 % display-power savings for a large dark background (VERIFIED, session 10083). Default the in-app player to a dark background.

---

## 4. Background execution

- **No background audio (`UIBackgroundModes: audio`) to stay alive.** Playing silent audio would earn the widget-budget exemption for an *"active audio session"* (VERIFIED list in §1.1). It would also:
  - keep our process running continuously
  - risk interrupting Spotify or taking audio focus from it
  - show up as background-audio time in MetricKit (`TotalBackgroundAudioTimeMetric`) and in Settings › Battery
  - break App Store Review Guideline 2.5.4 if the app is ever distributed
- **No location tricks.** *"Location services keep the device awake to continuously stream location"* (VERIFIED, WWDC22 10083). Significant-change monitoring also wakes the app at unpredictable times. Both cost far more than a dozen HTTP calls per hour.
- **No timers, `beginBackgroundTask` loops, or VoIP/PushKit abuse.** WWDC22 puts it as *"The key to limiting background runtime is to remember to tell the system when you are done."*
- **`BGAppRefreshTask`: low value. Do not ship it in v1.** The system schedules it based on usage, it runs only briefly, and it is meant *"for updating your app with small bits of information"* ([BGAppRefreshTask](https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask)). The run time and frequency are INFERRED to be about 30 s and a few times per day at most. It cannot follow track changes. The widget's own timeline already gives us opportunistic background fetches, so `BGAppRefreshTask` would only add wake-ups.
- **App Remote lifecycle (VERIFIED, [Spotify iOS application lifecycle guide](https://developer.spotify.com/documentation/ios/guides/application-lifecycle/)):** Spotify recommends **disconnecting in `applicationWillResignActive`** (SwiftUI: `scenePhase` becomes `.inactive`/`.background`) and reconnecting when the app becomes active again. Community reports say the SDK drops the connection when backgrounded and after about 30 s with nothing playing ([Spotify community thread](https://community.spotify.com/t5/Spotify-for-Developers/iOS-SDK-Disconnect-when-app-goes-to-background/td-p/5806965)). That is reported behaviour, not documented. Rules:
  - Disconnect explicitly.
  - Before disconnecting, write the last state to the App Group and call `WidgetCenter.reloadTimelines` once, which is free while still foreground.
  - Never auto-launch Spotify (`authorizeAndPlayURI`) just to reconnect.
  - Subscribe to player-state events instead of polling `getPlayerState`.
- **Live Activity (INFERRED from verified constraints):** a Live Activity cannot use the network, and without a server it can only be updated by our **app process**. That means only while the app is in the foreground, or inside occasional background tasks. Keeping it accurate in the background would need either a backend sending ActivityKit pushes (which have their own budget; see the [forum thread on budgets](https://developer.apple.com/forums/thread/731715)) or keep-alive tricks, which are rejected above. **Recommendation:** defer the Live Activity. If it is built, start it from the app, update it only from foreground App Remote events, show "last updated" honestly, and end it when the app has been backgrounded for more than ~10 min, since it will be stale. Do not set `NSSupportsLiveActivitiesFrequentUpdates`.

---

## 5. Low Power Mode and thermal state

- **VERIFIED** ([`isLowPowerModeEnabled`](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)): Low Power Mode reduces CPU and GPU performance and screen brightness, and pauses *"discretionary and background activities"*. Apps should observe `NSProcessInfoPowerStateDidChange` and *"take appropriate steps to reduce activity"*. Faster display refresh rates are disabled in Low Power Mode and when the device is hot ([ProMotion doc](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)).
- **VERIFIED** ([`ProcessInfo.ThermalState`](https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum)): `.nominal`, `.fair` ("slightly elevated"), `.serious` ("high"), `.critical` ("needs to cool down"). Observe `ProcessInfo.thermalStateDidChangeNotification`.
- **Does WidgetKit shrink the reload budget in Low Power Mode?** Apple's widget-update doc **does not say** (VERIFIED absence). It is INFERRED to be likely, since Low Power Mode pauses discretionary background activity, so background reloads may be deferred. **Measure it** with the reload log (§6.3). Do not assume either way.

**Our responses:**

| Condition | In-app rotation | Widget | Network | Live Activity |
|---|---|---|---|---|
| Normal | ≤ 60 fps CA animation | Spin; `.after(trackEnd)`, floor 5 min | As §1 | Foreground-only updates |
| **Low Power Mode** | 30 fps cap, or static if the user opts in to "Pause spin in Low Power Mode" | Extension reads `isLowPowerModeEnabled` at timeline time (INFERRED to work in extensions) → **static disc**, policy floor **15 min** | No image prefetch; art for the current album only | No updates; end it if stale |
| `thermalState == .fair` | 30 fps | Unchanged | Unchanged | Unchanged |
| `.serious` | **Stop rotation** | Static disc | Defer non-essential calls | Stop updating |
| `.critical` | Stop all animation | Static | Only user-initiated calls | End it |

---

## 6. Measurement without a Mac

### 6.1 Tools available

1. **Settings › Battery:** per-app share of battery over the last 24 h and 10 days, with screen-on vs. background activity (VERIFIED, [iPhone User Guide – battery usage](https://support.apple.com/en-us/guide/iphone/iphd453d043a/ios)). Two limits:
   - Resolution is coarse: whole percentages of total drain.
   - **Widget rendering and rotation are probably attributed to system processes** (Home & Lock Screen) rather than to our app, while the extension's own CPU and network may be attributed to us (INFERRED and UNVERIFIED; no Apple source found). **Per-app % alone will therefore understate widget cost.** Whole-device drain tests (§6.4) are needed.
2. **MetricKit:**
   - Reports cover the previous 24 h and arrive *"at most once per day"*. Diagnostics (crashes, hangs, CPU and memory exceptions) arrive immediately on iOS 15+ (VERIFIED, [MetricKit](https://developer.apple.com/documentation/metrickit), [MXMetricManager](https://developer.apple.com/documentation/metrickit/mxmetricmanager)).
   - **iOS 27:** the new `MetricManager` delivers `MetricReport`/`DiagnosticReport` through async sequences. New metrics such as `MetalFrameRateMetric` and the **memory-exception diagnostic** (useful for widget jetsams) exist only in the new API ([WWDC26 session 222](https://developer.apple.com/videos/play/wwdc2026/222/)). `MXMetricManager` is deprecated.
   - Useful metrics: `CPUTimeMetric`, `GPUTimeMetric`, `TotalCellularUpload/DownloadMetric`, `TotalWiFiUpload/DownloadMetric`, `PixelLuminanceMetric` (display), `TotalForeground/BackgroundTimeMetric`, `TotalBackgroundAudioTimeMetric` (must be 0), `PeakMemoryMetric`, `HitchTimeMetric`, `ForegroundTerminationMetric`/`BackgroundTerminationMetric` (app exit), `CellularConditionTimeMetric`, and signpost intervals through `mxSignpost`.
   - **Whether MetricKit covers the widget extension process is UNVERIFIED.** Design the Diagnostics screen so it does not depend on that.
   - Use `mxSignpost` intervals around "timeline build" and "spin active" to get per-feature CPU.
3. **On-device Power Profiler (iOS 26+, VERIFIED, [Measuring your app's power use with Power Profiler](https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler), [WWDC25 session 226](https://developer.apple.com/videos/play/wwdc2025/226)):**
   - Setup: Settings › Developer › Performance Trace → mode Power Profiler → enable our app → Control Center control. It records up to 10 h and shows per-process CPU, GPU, display, and networking power-impact lanes.
   - It **requires Developer Mode**, which normally appears once a development-signed build is installed (INFERRED for non-Xcode installs).
   - **Analysis requires Instruments on a Mac.** The trace (`.aar` → `.atrc`) can be shared to a borrowed or rented cloud Mac. The impact values are comparable only on the **same device model**, and charging zeroes system power.
   - This is the best way to see per-process **display and GPU** impact of the widget, if a Mac can be used once.
4. **Our own instrumentation** (§6.3): exact request counts, bytes, interface, reload counts, and animation-on time.

### 6.2 What the Diagnostics screen shows

All data is written to an App Group JSON-lines ring buffer (≤ 2,000 events, ≤ 1 MB) by both the app and the widget extension.

- **Network:**
  - every request: timestamp, endpoint (no tokens, no query PII), HTTP status, bytes sent and received, duration, interface (Wi-Fi, cellular, or other, via `NWPathMonitor` or `URLSessionTaskMetrics`), and origin (app, widget, or intent)
  - charts: requests per hour (24 h), requests per listening hour, cellular vs. Wi-Fi split, and **"radio bursts"**, meaning clusters of requests ≥ 15 s apart, which is the number that matters for tail energy
- **Widget:**
  - every `timeline(for:in:)` call: timestamp, reason (scheduled, app, intent, or unknown), cache hit or miss, wall time, peak `phys_footprint` (via `task_info`, logged), policy chosen, and entry count
  - per day: reloads per day vs. the 40–70 budget, and the gap between track change and widget update (lag)
- **App Remote:** connect and disconnect timestamps. **Alert if connected while the app is backgrounded for more than 2 s.**
- **Animation:** seconds of in-app spinning per day, fps cap in use, and time spent in Low Power Mode and in each thermal state.
- **Cache:** albums cached, total MB, hit rate, and evictions.
- **MetricKit:** the last 10 daily reports summarised (CPU s, GPU s, cellular and Wi-Fi MB, foreground and background time, peak memory, hitch ratio, exits) and every diagnostic (crash, memory exception, CPU exception, hang). Raw JSON is kept.
- **Battery samples:** `UIDevice.batteryLevel` and `batteryState` at app open and close. Resolution may be coarse (INFERRED).
- **Export:** a share-sheet button that exports everything as one JSON/CSV file, so it can be analysed on Windows (Excel or Python). There is no network upload and no analytics SDK.

### 6.3 Fair comparison protocol (our app vs. MD Vinyl vs. a no-widget baseline)

**Fixed conditions:**
- the same iPhone, iOS build, and battery health; note the starting temperature
- no charger, cases off or identical
- auto-brightness **off**, brightness fixed at 50 %, True Tone and Night Shift off, Low Power Mode off
- Spotify playlist **downloaded for offline play**, so streaming does not dominate network noise; same playlist, shuffle off, same volume, wired or the same Bluetooth headphones
- the same widget size and same Home Screen position, alone on its page; **only one** of the two vinyl widgets installed per run (remove the other widget; ideally offload the other app)
- Background App Refresh settings identical, other notifications silenced (Focus mode), iCloud Photos sync paused

**Scenarios, each 3 h:**
- **S1 "visible":** screen on with auto-lock Never, Home Screen showing the widget. This is the worst case for animation.
- **S2 "pocket":** screen off. This captures background reloads and networking.
- **S3 "in-app":** our app or MD Vinyl in the foreground, spinning.
- Run S1 and S2 on **Wi-Fi only** (cellular off) and on **cellular only** (Wi-Fi off) to isolate tail energy.

**Run order:**
- Start between 90 % and 80 % to avoid the non-linear region near 100 %.
- Rotate **A / B / Baseline** across days. Do at least **3 runs per arm**, alternating which arm goes first, at the same time of day.

**Record:**
- start and end battery %, and the Settings › Battery 24 h list
- our Diagnostics export
- if a Mac is available once, an on-device Power Profiler trace for one run per arm

**Report:**
- **drain over baseline** (%/h) per arm, with the range across runs
- request counts and widget lag for our app
- never a single-run number

**Limitations (state these with any result):**
- 1 % battery-gauge resolution means differences smaller than about 1–2 percentage points over 3 h cannot be resolved.
- Cell signal, temperature, battery wear, and background iOS work (Spotlight, iCloud, Photos) add day-to-day noise.
- MD Vinyl is a black box. Its update strategy may change between versions, and its widget may refresh differently.
- Per-app attribution in Settings misses render-server cost (§6.1).
- Spotify's own drain is shared by all arms but varies with codec and caching.
- n=3 runs gives only rough confidence.
- **Results support "no measurable difference at this resolution" or "X is clearly worse". They cannot support a claim of parity.**

---

## 7. Performance budget targets

These are proposed and INFERRED. Check them against Diagnostics and MetricKit during Phase 3.

| Area | Target |
|---|---|
| Web API requests, app foreground (App Remote connected) | **0** for track state |
| Web API requests, background, while playing | **≤ 12 currently-playing/h, ≤ 1 token refresh/h**; **≤ 4 radio bursts/h** averaged per day |
| Web API requests, idle (nothing playing > 2 h) | **≤ 1/h, target 0** (`.never` + app/intent) |
| Requests per day (all) | **≤ 100**; reloads within the 40–70 budget, no 429s |
| Image downloads | **≤ 1 per album ever** while it stays in cache; hit rate **≥ 90 %** on repeat listening |
| Data per listening hour | **≤ 0.5 MB** (JSON ~2–5 KB + new-album art ~20–50 KB each) |
| Network timeouts | request timeout **8 s**; **no retries** inside one timeline build |
| Widget extension peak memory | **≤ 15 MB** (half the observed 30 MB limit); **0** memory-exception diagnostics |
| Widget timeline build wall time | **≤ 1 s** from cache, **≤ 3 s** with network, p95 |
| Widget images | ≤ target pixel size per family (never above ~700 k px); ≤ 2 images per entry; ≤ 3 entries per timeline |
| Image cache on disk | **≤ 25 MB / 100 albums**, LRU |
| In-app CPU while spinning (steady state) | **≤ 3 % of one core** on the main thread with CA animation; main thread otherwise idle |
| In-app frame rate | **≤ 60 fps** normal, **≤ 30 fps** in Low Power Mode or thermal ≥ fair, **0** when not active or paused |
| Hitches | MetricKit hitch time ratio **< 5 ms/s** |
| Background runtime | MetricKit background audio and location time **= 0**; background time ≈ only OS-granted suspension |
| App Remote | disconnected **≤ 1 s** after resign-active; **0** auto-launches of Spotify |
| Live Activity (if built) | updates only from foreground; ended **≤ 10 min** after the app backgrounds; no frequent-updates entitlement |
| Battery (goal, not a claim) | S2 pocket: **indistinguishable from baseline** at gauge resolution. S1 visible: drain over baseline **as small as measurable**, reported per §6.3. |

---

## 8. Optimization rules for implementers

1. **Make one radio burst per reload.** Do the token refresh, currently-playing call, and album art together, sequentially and within seconds, never spread out.
2. **Read the App Group cache before any network call.** If the app or a recent reload wrote state in the last 60 s, use it.
3. **Never poll.** No timers, no `while` loops, no `BGAppRefreshTask` in v1. The timeline policy, App Remote events, and App Intents are the only triggers.
4. **Use `.after(trackEnd + grace)` with a ≥ 5 min floor.** Back off to 60 min or `.never` when paused or idle. Add a "stale → stop spinning" entry.
5. **Make foreground reloads free.** On App Remote state change, write the App Group state and call `reloadTimelines(ofKind:)` (debounced 2 s). Do a final reload just before disconnecting on resign-active.
6. **Use the budget-exempt refresh button (`Button(intent:)`)** to fix stale content, rate-limited to one network call per 10 s.
7. **Keep album art at the right size and fetched once.** Use 300 px, ImageIO thumbnailing to the exact pixel size, a pre-composited disc PNG, and LRU caching by album ID. Never `AsyncImage` in widgets. Never full-size decode.
8. **Rotate one flattened layer.** Keep shadows, blurs, and masks static and outside the rotating layer. Give any shadow a `shadowPath`.
9. **In the app, use `CABasicAnimation` (render server) and avoid per-frame main-thread work.** No `TimelineView(.animation)` or `CADisplayLink` angle updates. Cap at 60 fps and do not add `CADisableMinimumFrameDurationOnPhone`.
10. **Pause animation unless the app is active, visible, and playing.**
11. **Respond to Low Power Mode and thermal state** following the §5 table.
12. **Prohibit keep-alive tricks:** no background audio, no location, no VoIP, no silent pushes.
13. **Use a dark default player UI** for OLED savings.
14. **Instrument everything** into the App Group Diagnostics log, with no tokens or PII in logs, from day one.
15. **Handle 429 and errors politely.** Honour `Retry-After` and never retry immediately in the extension.
16. **Keep a public fallback** (static disc plus `ProgressView(timerInterval:)`) behind a flag in case `_clockHandRotationEffect` breaks in an iOS update.

---

## 9. Open questions / to verify in Phase 2–3

- Is the widget's 30 MB limit shared across all families in one extension, and did iOS 27 or the extra-large size change it? (Measure with logged `phys_footprint` and MetricKit memory-exception diagnostics.)
- Does Low Power Mode reduce or defer WidgetKit reloads? (Measure with the reload log.)
- Does the system cap the frame rate of `_clockHandRotationEffect`, and is it suspended in StandBy or Always-On? (Power Profiler display lane, if a Mac can be used.)
- Is widget render cost attributed to our app or to "Home & Lock Screen" in Settings › Battery?
- Does MetricKit report metrics for the widget extension process?
- What is the actual `currently-playing` payload size with `market=from_token`?
- What are 5G NR tail-energy figures for current iPhones?

## 10. Sources

- Apple, Keeping a widget up to date: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- Apple, Displaying dynamic dates in widgets: https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates
- Apple, Making network requests in a widget extension: https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension
- Apple, Creating a widget extension: https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension
- Apple, Updating widgets with WidgetKit push notifications: https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications
- Apple, WWDC25 "What's new in widgets" (278): https://developer.apple.com/videos/play/wwdc2025/278/
- Apple, Energy Efficiency Guide for iOS Apps – Energy and Networking: https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/EnergyandNetworking.html
- Apple, WWDC22 "Power down: Improve battery consumption" (10083): https://developer.apple.com/videos/play/wwdc2022/10083/
- Apple, WWDC25 "Profile and optimize power usage in your app" (226): https://developer.apple.com/videos/play/wwdc2025/226
- Apple, Measuring your app's power use with Power Profiler: https://developer.apple.com/documentation/xcode/measuring-your-app-s-power-use-with-power-profiler
- Apple, MetricKit: https://developer.apple.com/documentation/metrickit ; MXMetricManager: https://developer.apple.com/documentation/metrickit/mxmetricmanager ; WWDC26 "Meet the new MetricKit" (222): https://developer.apple.com/videos/play/wwdc2026/222/
- Apple, ProcessInfo.isLowPowerModeEnabled: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled ; ThermalState: https://developer.apple.com/documentation/foundation/processinfo/thermalstate-swift.enum
- Apple, Optimizing iPhone and iPad apps to support ProMotion displays: https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays ; CADisplayLink.preferredFrameRateRange: https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange
- Apple, ImageIO CGImageSourceCreateThumbnailAtIndex: https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:) ; WWDC18 "Image and Graphics Best Practices" (219): https://developer.apple.com/videos/play/wwdc2018/219/
- Apple, Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities
- Apple, BGAppRefreshTask: https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask
- Apple, iPhone User Guide – battery usage: https://support.apple.com/en-us/guide/iphone/iphd453d043a/ios
- Apple Developer Forums (widget memory/image limits): https://developer.apple.com/forums/thread/713561 , https://developer.apple.com/forums/thread/733347 , https://developer.apple.com/forums/thread/842805 , https://developer.apple.com/forums/thread/795793 , https://developer.apple.com/forums/thread/778731 , https://developer.apple.com/forums/thread/773785 , https://developer.apple.com/forums/thread/710745 ; Live Activity budget: https://developer.apple.com/forums/thread/731715
- Spotify, Web API rate limits: https://developer.spotify.com/documentation/web-api/concepts/rate-limits ; iOS application lifecycle: https://developer.spotify.com/documentation/ios/guides/application-lifecycle/ ; community disconnect reports: https://community.spotify.com/t5/Spotify-for-Developers/iOS-SDK-Disconnect-when-app-goes-to-background/td-p/5806965
- Huang et al., "A Close Examination of Performance and Power Characteristics of 4G LTE Networks", MobiSys 2012: https://www.cs.sjtu.edu.cn/~xue-gt/wireless/Paper/Energy%20efficiency%20of%20cellular%20network%20and%20smartphone/A%20Close%20Examination%20of%20Performance%20and%20Power.pdf
- Narayanan et al., "A Variegated Look at 5G in the Wild", SIGCOMM 2021: https://www-users.cse.umn.edu/~fengqian/paper/5g_sigcomm21.pdf
- Community: ClockHandRotationKit: https://github.com/octree/ClockHandRotationKit ; Scripting app widget animation guide: https://scriptingapp.github.io/guide/Widget/Animation%20for%20Widget%20and%20LiveActivity
- 9to5Mac, iOS 27 extra-large widgets: https://9to5mac.com/2026/06/08/ios-27-adds-extra-large-widgets-for-your-extra-large-needs/
