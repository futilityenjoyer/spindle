# 04 — Animation: making the vinyl spin continuously on every surface

**Agent 4: Animation Specialist** · Phase 1 research · 2026-11-11
**Status:** research only. The snippets are illustrative and have not been compiled.

Labels used throughout:
- **VERIFIED**: confirmed directly in the cited primary or first-hand source (Apple docs, source code, issue thread).
- **INFERRED**: my reasoning from the cited evidence. It still needs testing on a device.
- **UNVERIFIED**: claimed by a secondary source, or contradicted between sources.

> **Correction to the brief.** The brief says "current iOS is 26.x". In fact iOS 27 shipped on 14 Sep 2026 (MacRumors, https://macrumors.com/2026/09/13/ios-27-release-date-new-features/, VERIFIED). Community reports already cover private-API behaviour on iOS 27 / Xcode 27 (see §1.4). The project should target iOS 26 and 27 and test on both.

---

## 0. TL;DR

| Surface | Recommended mechanism | Continuous? | Public API? | Confidence |
|---|---|---|---|---|
| Home-screen widget | WidgetKit's private `_ClockHandRotationEffect`, built at runtime by the open-source **ClockHandKit** (MIT, source-only). A static branch is used when paused. | **Yes**, render-server driven, a function of wall-clock time | **No** (private) | Medium: works today on iOS 26.1+/27 per community reports; Apple has already broken it once |
| Widget fallback | A static disc plus iOS 17+ entry transitions (≤2 s), with an optional `ProgressView(timerInterval:)` progress ring | No | Yes | High |
| Live Activity (Lock Screen / Dynamic Island) | Static disc and `Text(timerInterval:)` / progress. Trying ClockHandKit here is **experimental** | Unknown | — | Low (no evidence either way) |
| Companion app | **Core Animation** `CABasicAnimation` on `transform.rotation.z` in a `UIViewRepresentable`. Inertia comes from analytic Bezier ramps; pause/resume uses the presentation angle | Yes | Yes | High |

**Can a third-party home-screen widget continuously rotate a vinyl? Conditional yes.**
- **Public APIs alone: no.**
- **With the private WidgetKit effect: yes.**
  - It works today on iOS 17, 18, 26.0, 26.1+ and 27, but only through runtime construction (ClockHandKit). The old `_clockHandRotationEffect` wrappers were neutered for apps built with the iOS 26.1+ SDK.
  - This is exactly what shipping apps such as MD Vinyl ("Now Spinning" widget) appear to rely on (INFERRED).
  - It can break with any iOS release, so the widget must degrade gracefully to a static disc.

---

## 1. Home-screen widget: `_clockHandRotationEffect` / `_ClockHandRotationEffect`

### 1.1 Does it exist, and where does it live?

- **The effect type is `WidgetKit._ClockHandRotationEffect`**, a struct, not a SwiftUI symbol.
  - ClockHandKit looks it up at runtime with `_typeByName("9WidgetKit24_ClockHandRotationEffectV")`. In Swift mangling, `9WidgetKit` is the module and `24_ClockHandRotationEffect` is the type name.
  - The type conforms to `Decodable` and `ViewModifier`.
  - Source: https://raw.githubusercontent.com/giljihun/ClockHandKit/main/Sources/ClockHandKit/ClockHandRotationEffect.swift (VERIFIED by reading the source).
- **A view-extension entry point, `_clockHandRotationEffect(...)`, used to be callable.**
  - Apple's Clock widget uses it to sweep its hands.
  - Bryce Bostwick found it by extracting the Clock widget binary from an IPSW and disassembling it ("This clock should not be possible to make", YouTube `NdJ_y1c_j_I`, summary at https://youtubesummary.com/summary/NdJ_y1c_j_I; Hackaday write-up at https://hackaday.com/2025/05/17/animated-widgets-on-apple-devices-via-a-neat-backdoor). UNVERIFIED secondary summary, but consistent with everything else.
- **Xcode 14 hid it from the public interface.**
  - A developer reported it "has been disabled in Xcode 14" (Apple Developer Forums, https://developer.apple.com/forums/thread/720640, Nov 2022, VERIFIED as a user report).
  - The workaround was to compile a wrapper with Xcode 13.3, whose SDK still exposed it. That wrapper is octree's ClockHandRotationKit; see the maintainer in https://api.github.com/repos/octree/ClockHandRotationKit/issues/2/comments (VERIFIED).
  - This is why every package ships either a **prebuilt binary** (octree) or a **runtime reflection** bridge (ClockHandKit).
- **No Apple documentation exists for it.** It appears in no `developer.apple.com` page. Treat it as private API.

### 1.2 Signatures and period options

| Source | Signature | Status |
|---|---|---|
| Apple's original underscored modifier, as quoted in a Stack Overflow answer and the Apple forum thread above | `._clockHandRotationEffect(.secondHand, in: .current, anchor: .center)` | UNVERIFIED (no SDK `.swiftinterface` is public today; a blog renders it differently: `._clockHandRotationEffect(period:timeZone:anchor:)`, https://blog.andreszenteno.com/notes/apples-widget-backdoor) |
| octree/ClockHandRotationKit `.swiftinterface` (Swift 5.6.1 / Xcode 13.3, iOS 14 deployment target) | `enum ClockHandRotationPeriod { case custom(TimeInterval), secondHand, minuteHand, hourHand }`; `struct ClockHandRotationModifier: ViewModifier { init(period:timeZone:anchor:) }`; `extension View { func clockHandRotationEffect(period:in:anchor:) -> some View }` (timeZone defaults to `.current`, anchor to `.center`) | VERIFIED: https://raw.githubusercontent.com/octree/ClockHandRotationKit/main/ClockHandRotationKit.xcframework/ios-arm64/ClockHandRotationKit.framework/Modules/ClockHandRotationKit.swiftmodule/arm64-apple-ios.swiftinterface |
| giljihun/ClockHandKit (Swift tools 6.2, iOS 16+) | `ClockHandPeriod { .hourHand (43 200 s), .minuteHand (3 600 s), .secondHand (60 s), .custom(Double) }`; `View.clockHandRotationEffect(period: ClockHandPeriod, in: TimeZone = .current, anchor: UnitPoint = .center)` plus a `period: TimeInterval` overload for drop-in migration from octree | VERIFIED (source file above) |
| Private decodable payload ClockHandKit sends to WidgetKit | JSON keys `period` (seconds), `timeZone`, `anchor` (`[x, y]` doubles), `honorIdealizedDate` (always `false`; a code comment says WidgetKit 27 *requires* the key) | VERIFIED as ClockHandKit's implementation. The key layout is Apple-private and may change |

`period` is the time for one full 360° turn (ClockHandKit README, https://github.com/giljihun/ClockHandKit, VERIFIED). A 33⅓ RPM disc is therefore `.custom(1.8)`, and 16⅔ RPM is `.custom(3.6)`.

### 1.3 Minimum iOS version

- **iOS 14:** octree's prebuilt wrapper targets iOS 14 (Package.swift, https://raw.githubusercontent.com/octree/ClockHandRotationKit/main/Package.swift, VERIFIED). Home-screen widgets arrived in iOS 14, together with Apple's Clock widget.
- **iOS 16:** ClockHandKit declares `@available(iOS 16.0, *)` (VERIFIED).
- **Project floor:** our project floor will be iOS 17 or later anyway, for widget animations and interactivity. So the minimum is not a constraint.

### 1.4 Does it still work on iOS 17, 18, 26 and 27? (the crucial history)

Source: octree issue #11, https://github.com/octree/ClockHandRotationKit/issues/11, with comments at https://api.github.com/repos/octree/ClockHandRotationKit/issues/11/comments (all VERIFIED as user reports).

| Build Xcode → runtime iOS | octree (prebuilt, calls `_clockHandRotationEffect`) | ClockHandKit (runtime-decoded `_ClockHandRotationEffect`) |
|---|---|---|
| Xcode 26.1 → iOS 17.5 / 18.6 / 26.0.1 | Works | n/a |
| Xcode 26.0.1 → iOS 26.1 … 26.5 | Works (reports dated 2025-12-17 and 2026-05-27) | n/a |
| Xcode 26.1 / 26.1.1 / 26.2b1 → iOS 26.1+ | **Broken.** The function "returns the view unchanged in third-party apps" | Works (README demo) |
| Xcode 27.0 → iOS 27 | Broken (presumably) | **Works** (reported 2026-10-03 by platadani in #11) |

Additional details:
- **iOS 18 / iOS 26 also work** (issue #10, https://github.com/octree/ClockHandRotationKit/issues/10). One reporter could not get it working on iOS 26 at first; the issue was later closed as completed.
- **TestFlight caveat.** The prebuilt octree binary contained a deprecated bitcode segment. That made App Store Connect reject the upload (#9). In a TestFlight build it caused the widget to advance "one frame per tap" (#13, merged 2026-03-11).

**INFERRED interpretation.** The pattern is "works if built with the SDK before 26.1, broken if built with 26.1+, on runtime 26.1+". That looks like a deliberate **linked-on-or-after gate**: Apple chose to stop honouring the old entry point for third-party binaries built against newer SDKs. ClockHandKit gets around the gate by constructing the internal struct directly. It has already had to add a new key for WidgetKit 27 (`honorIdealizedDate`). **Apple is actively changing this path.** Expect breakage at any major, or even point, release.

### 1.5 Surfaces: widget, Live Activity, StandBy

| Surface | Status | Evidence |
|---|---|---|
| Home-screen widgets (all sizes) | **Works** | All sources above; GIF-in-widget articles (https://juejin.cn/post/7399984522093838363, https://juejin.cn/post/7426696679247347766) |
| StandBy (widget stack) | **Probably works in normal mode** (INFERRED: StandBy shows ordinary WidgetKit widgets, and Apple's Clock widget sweeps there). In Night Mode / dimmed state, expect `isLuminanceReduced` and no animation (INFERRED) | Apple doc: "In StandBy, the system refreshes your widget's display at a system-defined rate" (https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date.md, VERIFIED) |
| Lock Screen widgets (accessory families) | Unknown; untested. Plausible, since it is the same WidgetKit renderer (INFERRED) | none found |
| Live Activities (Lock Screen + Dynamic Island) | **Unknown: no public report found either way** | Searches in English and Chinese found nothing. ActivityKit docs say the system "ignores any animation modifiers … and uses the system's animation timing" (https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities.md, VERIFIED). `_ClockHandRotationEffect` is not an animation modifier but a time-driven effect, so it *might* still render (INFERRED, must be tested) |
| Always-On display | **Expect no motion.** Apple: "On devices that include an Always-On display, the system doesn't perform animations to preserve battery life in Always On" (https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities.md, VERIFIED for normal animations; INFERRED for the clock-hand effect). Check `isLuminanceReduced` and render static |
| Low Power Mode | **Expect ticking, not a smooth sweep.** One developer observed Apple's own Clock icon/widget "ticks" in Low Power Mode and sweeps smoothly otherwise (octree #11 comment, 2025-11-09, VERIFIED as a report). For a 1.8 s/rev vinyl, a 1 Hz tick would mean ~200° jumps, which looks terrible. Must be tested; see §1.8 |

### 1.6 Is the angle a pure function of wall-clock time?

- **VERIFIED in spirit.**
  - ClockHandKit's README: the effect "rotates the view based on the current time rather than waiting for a new timeline".
  - Its payload comment: `honorIdealizedDate = false` means "rotate by the real current time, not the idealized preview time".
  - The `secondHand` period with a `timeZone` parameter can only show the correct time if angle = f(local wall-clock time).
- **INFERRED formula:** angle(t) = 360° × frac((seconds since a local-time epoch, probably local midnight in `timeZone`) / period). The exact epoch for `.custom` periods is not documented and **must be calibrated on a device** (see §1.8).

Consequences, all INFERRED but strongly supported by the mechanism:
1. **No reset on timeline reloads or track changes.**
   - The widget extension does not run the animation. The system renderer evaluates f(now) every frame.
   - A new timeline entry, a reload, even a brand-new view tree all draw the disc at the same phase at the same instant. There is no visible jump, *provided the period and the static pre-rotation stay the same*.
   - This is the property we need for "doesn't reset when the track changes".
2. **The phase is shared across every instance and every surface using the same period.** Two widgets on screen spin in perfect lockstep.
3. **You cannot ease speed.** There is no spin-up or spin-down inertia: the disc is either at full speed or static. Any "inertia" has to be faked with an entry transition (≤2 s), see §1.7.

### 1.7 Applying it conditionally per timeline entry (play/pause)

- **Yes**, it is an ordinary view modifier, so you can apply it or not per entry (INFERRED from its `ViewModifier` nature, VERIFIED above).
- When the entry says paused, render a static `rotationEffect(phaseAngle(at: entry.date))`. That freezes the disc at roughly where the clock-driven effect would have been at render time, so there is no jump on pause apart from render latency.
- **Resume jump.**
  - When playback resumes, the clock-driven angle is f(now). That is unrelated to the frozen angle, so the disc snaps to a new phase.
  - Mitigation: pre-rotate the spinning view by a static offset Δ = θ_paused − f(t_render), applied **inside** the clock-hand effect.
  - Residual error = (display time − render time) × angular speed. At 16⅔ RPM (100°/s), a 300 ms latency gives 30°; at 33⅓ RPM it gives 60°.
  - Alternatively, mask the switch with an `.opacity` transition. Widgets support up to 2 s transitions: "Animations in widgets and Live Activities have a maximum duration of two seconds" (https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities.md, VERIFIED).
- **Avoid structural identity churn.**
  - Switching between `if playing { spinning } else { static }` changes view identity, and WidgetKit will cross-fade by default ("If you add or remove views … views fade in and out", same doc, VERIFIED).
  - That fade is actually a decent "needle lift" cue. Make it deliberate with `.transition(.opacity)` rather than accidental.
- **Pause latency is the real limitation.**
  - The widget only learns about the pause when its timeline is reloaded. Our app is **not** the Now Playing app (Spotify is), so reloads come out of the 40–70/day budget.
  - The reload exemption only applies when "The widget's containing app is the current Now Playing app" (https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date.md, VERIFIED).
  - Pause/resume freshness is therefore an architecture and data problem (Agents 1/5), not an animation one. Animation-wise, a late pause just means the disc keeps spinning until the next reload.
  - **Design rule:** every timeline the provider returns for a playing track should end with a **paused/stopped entry at the predicted track end**. Then the disc stops on its own if no further reload arrives.

### 1.8 Known glitches and open questions (test plan)

| Issue | Evidence | Mitigation |
|---|---|---|
| Silently no-ops (returns the unmodified view) if Apple changes the private type or keys | ClockHandKit logs every failure path and falls back to the original view (source, VERIFIED) | Design the static disc to look good. A non-spinning vinyl is an acceptable degraded state |
| Anchor/offset ordering: rotating after an `.offset` swings the view around the wrong centre | "rotate first, then set offset" (https://juejin.cn/post/7399984522093838363, VERIFIED) | Apply the effect to a **square, centred** disc view with `.center` anchor *before* any offset/position; use `.frame(width:height:)` on the disc itself |
| Seams/"tearing" in multi-arc GIF tricks | Same juejin article | Not relevant: we rotate one bitmap |
| Low Power Mode ticking | octree #11 comment | Measure on device. If it ticks at 1 Hz, the app writes `lowPowerMode` into the shared state at timeline time and the widget renders static. LPM changes don't trigger reloads, so this is best-effort (INFERRED) |
| Real render cadence on the Home Screen unknown | ClockHandKit README: "WidgetKit and the device decide the actual rendering cadence" (VERIFIED). One video summary claims ~20 FPS for clock-hand animation (UNVERIFIED) | Measure with a 60 fps screen recording and count distinct angles per second. If cadence is ~20–30 fps, prefer the slower 16⅔ RPM (§4) to keep per-frame steps small |
| Epoch of `.custom` periods | Undocumented | Calibrate: render a `.custom(60)` hand next to `.secondHand` and compare; then `.custom(3.6)` against a computed angle |
| Off-screen widgets | WidgetKit renders out-of-process; rarely visited pages get fewer reloads (keeping-a-widget-up-to-date doc, VERIFIED) | Off-screen views are not composited, so the cost should be zero (INFERRED) |
| Mixing octree and ClockHandKit | "Don't import ClockHandKit and ClockHandRotationKit into the same target" (README, VERIFIED) | Use ClockHandKit only |

### 1.9 Open-source wrappers: evaluation

| Package | Mechanism | Licence | Quality notes | Verdict |
|---|---|---|---|---|
| **giljihun/ClockHandKit** (https://github.com/giljihun/ClockHandKit), ~26★, active (last commits 2026-10-03), 42 commits | **Source-only.** `_typeByName` → JSON-encode `{period,timeZone,anchor,honorIdealizedDate}` → `JSONDecoder` into the private type → cast to `any ViewModifier` → apply. Returns `AnyView` | MIT (© 2026 GIL) (https://raw.githubusercontent.com/giljihun/ClockHandKit/main/LICENSE, VERIFIED) | Small (one source file plus tests), readable, logs via `os.Logger`, graceful fallback, has payload unit tests and an example widget. Needs Swift tools 6.2 (Xcode 26+), no dependencies (Package.swift, VERIFIED). `AnyView` erasure is harmless in a widget | **Recommended.** Vendor it (copy the single file) so a CI build never depends on the remote repo |
| octree/ClockHandRotationKit (https://github.com/octree/ClockHandRotationKit), 149★ | Prebuilt XCFramework compiled with Xcode 13.3; **no source** (issue #12 asks for it) | MIT | Binary blob (maintainer: "you'd better build an XCFramework yourself"); had a bitcode problem; broken with Xcode ≥ 26.1 | **Avoid.** Opaque binary, dead on modern SDKs |
| b5nt/CHRK (https://github.com/b5nt/CHRK) | Fork of octree | MIT | 0★ fork | Avoid |

Illustrative widget usage (ClockHandKit API; not compiled):

```swift
import SwiftUI
import WidgetKit
import ClockHandKit   // vendored, single file, MIT

struct VinylDisc: View {
    let entry: NowPlayingEntry              // isPlaying, trackID, labelImage, pausedAngle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var dimmed

    private let period: TimeInterval = 3.6  // 16⅔ RPM on the widget (see §4)

    var body: some View {
        ZStack {
            spinningPart                     // grooves + label: the ONLY rotating child
            Image("sheen").resizable()       // static specular highlight (§5)
                .allowsHitTesting(false)
            Image("tonearm").resizable()     // static
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder private var spinningPart: some View {
        let disc = ZStack {
            Image(uiImage: entry.groovesBitmap).resizable()   // pre-rendered, radially symmetric
            Image(uiImage: entry.labelBitmap).resizable()     // pre-cropped circle, alpha
                .padding(entry.labelInset)
                .id(entry.trackID)                            // new track => cross-fade inside the spinning layer
                .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)     // square, centred BEFORE rotating

        if entry.isPlaying && !reduceMotion && !dimmed {
            disc
                .rotationEffect(.degrees(entry.resumeOffsetDegrees)) // optional phase-matching Δ (§1.7)
                .clockHandRotationEffect(period: .custom(period))    // render-server, wall-clock driven
                .transition(.opacity)
        } else {
            disc
                .rotationEffect(.degrees(entry.pausedAngle))         // frozen phase
                .transition(.opacity)
        }
    }
}
```

### 1.10 Risk assessment

| Risk | Likelihood | Impact | Notes |
|---|---|---|---|
| Apple neuters the runtime path (as they did the function entry point in 26.1) | **Medium–high over 12 months** (INFERRED from the 26.1 gate and the 27 key change) | Widget stops spinning, but still renders | ClockHandKit falls back to the unmodified view, so the widget stays usable |
| App Review rejection (if ever submitted) | **Medium** | Rejection | Guideline 2.5.1: "Apps may only use public APIs" (https://developer.apple.com/app-store/review/guidelines/, VERIFIED). `_typeByName` with a literal mangled `WidgetKit` type name is easy to spot by string scanning (INFERRED). Counter-evidence: App Store apps visibly ship spinning widgets. MD Vinyl's 3.8.2 notes: "Meet Now Spinning, a new widget that brings album art and spinning vinyl together" (https://apps.apple.com/us/app/id1606306441, VERIFIED). Its technique is INFERRED to be this effect. The octree owner's answer to "will Apple detect it?" (#5) was a bare "不会" ("it won't"), anecdotal. **For a sideloaded personal app, App Review is moot** |
| Apple DTS stance | — | — | A DTS engineer on custom widget animation: "There is a hack some developers have figured out but it is not supported by the system and cannot be recommended … Can cause battery drain" (https://developer.apple.com/forums/thread/757696, VERIFIED) |
| Toolchain coupling (cloud CI) | Low with ClockHandKit | — | Source package, builds with whatever Xcode 26/27 the CI image has. The octree approach would require pinning **Xcode 26.0.1**, which is fragile on hosted runners |

**Fallback if it disappears (ordered):**
1. A static vinyl with label art. The iOS 17+ content transition on the label (blur/fade, ≤2 s) still makes track changes feel alive.
2. A `ProgressView(timerInterval:)` ring around the disc for track progress. It is public, updates without reloads, and pauses only on reload (https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates.md, VERIFIED).
3. Tap → open the app, where the full Core Animation disc lives.

---

## 2. Other widget options and why they fall short

| Option | What it can do | Why it fails for a continuous vinyl | Source |
|---|---|---|---|
| iOS 17+ entry animations / `contentTransition` / `.transition` / `animation(_:value:)` | Animates **between** timeline entries. "Widgets and Live Activities support all built-in SwiftUI transitions and animations" | **Max 2 s** per animation, and only on an entry change. "Transaction isn't available to widgets". No repeat-forever | https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities.md (VERIFIED) |
| Entry-driven rotation (iOS 17 interpolates `rotationEffect` between entries) | A monotonically increasing angle animates smoothly from entry to entry (David Smith's clock widget) | You would need an entry every ≤2 s with a linear 2 s animation. Apple asks for entries "at least about 5 minutes apart" (doc below). Even if honoured, an hour of playback = 1 800 entries; the extension must render or archive each view (INFERRED: heavy) | https://www.david-smith.org/blog/2023/11/06/design-notes-46/ (VERIFIED); https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date.md (VERIFIED) |
| Pre-rendered frame timelines (one entry per frame) | Flip-book | **Quantified.** The budget is "from 40 to 70 refreshes" per day, "roughly … every 15 to 60 minutes", entries ≥ ~5 min apart (VERIFIED, same doc). A 33⅓ RPM disc at a crude 12 frames/rev needs 6.7 entries/s ≈ **24 000 entries per hour**, about four orders of magnitude off. Each entry is a full view render, and none can be guaranteed to display at sub-second precision | same |
| `Text(timerInterval:)` / `.timer` + custom font glyphs | Public API; the system updates the text once per second without running the extension | ~1 fps per timer. Bostwick reached ~30 FPS only with ~16 fonts × ~17 overlapping timers (summary, UNVERIFIED). Glyphs are baked into font files at build time, so **per-track album art cannot be put in a glyph**. Apple DTS suggested the font trick for GIF-like 1 fps animation only (https://developer.apple.com/forums/thread/720640, VERIFIED; https://developer.apple.com/forums/thread/757696, VERIFIED). Public sample: https://github.com/brycebostwick/WidgetAnimation (MIT, "8 FPS … up to 30 FPS") | Not viable for a rotating, per-track label |
| `ProgressView(timerInterval:countsDown:)` | Auto-filling linear or circular progress, no reloads | It fills, it does not rotate arbitrary content. Useful as a **track-progress ring** around the disc | https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates.md (VERIFIED) |
| `TimelineView`, `Timer`, `CADisplayLink`, `repeatForever` inside a widget | — | The widget extension "is not continually active, even if the widget is onscreen" (keeping-a-widget-up-to-date, VERIFIED); `Timer`/`CADisplayLink` reported "invalid" in widgets (forum 720640, VERIFIED report) | — |

---

## 3. Companion app: animation architecture

### 3.1 Comparison

| Option | Per-frame work | Main-thread involvement (steady state) | Pause/resume without jumps | Inertia | Verdict |
|---|---|---|---|---|---|
| **(a) Core Animation `CABasicAnimation` on `transform.rotation.z`** | Render server rotates a cached bitmap on the GPU. "Core Animation passes the layer's bitmap and state information to the graphics hardware"; "does all of the frame-by-frame drawing for you in hardware" (https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html, VERIFIED). Once committed, frames render "without the need for inter-process communication" (WWDC14 419 notes, https://www.wwdcnotes.com/notes/wwdc14/419, VERIFIED secondary) | **None** | Easy: `layer.speed/timeOffset/beginTime` (Apple QA1673, https://developer.apple.com/library/archive/qa/qa1673/_index.html, VERIFIED), or read `presentation()` and rebuild | Exact via timing functions (§3.2) | **Recommended** |
| (b) SwiftUI `TimelineView(.animation)` + `rotationEffect(angle(t))` | Re-evaluates the content closure every frame (TimelineView "redraws the content it contains at scheduled points in time", https://developer.apple.com/documentation/swiftui/timelineview.md, VERIFIED) | Yes, small: one closure plus a diff per frame | Trivial: angle is an analytic f(t) | Trivial: integrate a velocity curve | Good runner-up. Simplest code. `.animation(minimumInterval:paused:)` gives a built-in pause and frame cap (https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:).md, VERIFIED) |
| (c) SwiftUI `.linear.repeatForever` on `rotationEffect` | Built-in effects animate "off the main thread and without calling into any of your view code" (WWDC23 "Explore SwiftUI animation", https://developer.apple.com/videos/play/wwdc2023/10156/, VERIFIED) | Low | **Hard.** SwiftUI exposes no presentation value, so stopping "where it is" is not possible without tracking time yourself. Community reports of backwards steps after backgrounding (https://developer.apple.com/forums/thread/826682, May 2026, unresolved) and CPU creep with `repeatForever` (https://developer.apple.com/forums/thread/767243) | Awkward | Avoid |
| (d) `CADisplayLink` driving `transform` | Main-thread callback every frame, plus a CA commit every frame | **Every frame** | Easy | Easy | Avoid (most power-hungry; only worth it for physics) |

**Recommendation: (a) Core Animation**, hosted in SwiftUI via `UIViewRepresentable`.
- In steady state the app does **zero** per-frame work. The render server rotates one cached bitmap.
- The only main-thread work happens on events: play, pause, track change, scene change.
- Use (b) if the team prefers pure SwiftUI. Its cost is small but non-zero per frame. Pass `paused: true` whenever the disc is idle.

### 3.2 Inertia without angle jumps (spin-up / spin-down)

**Reference timing.** Technics direct-drive turntables are specified at **0.7 s from standstill to 33⅓ rpm** (Technics SL-1200M7L specs, https://www.technics.com/nz/products/dj-series/sl-1200m7l.specs.html; Stereophile, https://www.stereophile.com/content/technics-sl-1200gmesl-1210gme-turntable-specifications, VERIFIED). Use spin-up **0.7 s** and spin-down **~1.0 s** (a design choice: a lifted needle coasting with light braking).

**Exact Bezier timing for a linear velocity ramp** (my derivation; INFERRED, easy to unit-test):
- To ramp angular velocity linearly from v₀ to v₁ over duration τ, rotate by Δθ = τ·(v₀+v₁)/2.
- Use `CAMediaTimingFunction(controlPoints: 1/3, a/3, 2/3, (a+1)/3)` with **a = 2v₀/(v₀+v₁)**.
- Because the x control points are evenly spaced, the curve's x is linear in its parameter, and y(u) = a·u + (1−a)·u², which is exactly constant acceleration.

| Case | Values | Control points | Angle covered |
|---|---|---|---|
| Spin-up | v₀=0 → a=0 | (1/3, 0, 2/3, 1/3) | ω·τ/2 |
| Spin-down | v₁=0 → a=2 | (1/3, 2/3, 2/3, 1) | ω·τ/2 |

Velocities match at every junction, so there is no kink and no jump.

**Steady state.** Add a second animation, `byValue: 2π`, `duration: T`, `repeatCount: .infinity`, with `beginTime = rampEnd`, on a different key. Before its `beginTime` it is inactive (default fill mode), so the ramp shows. Afterwards it takes over seamlessly.

**Interrupting a ramp** (pause during spin-up):
- Keep a tiny analytic model of (t₀, θ₀, v₀, v₁, τ) on the main thread.
- Compute θ(now) and v(now) analytically rather than trusting `presentation()`. `presentation()` is fine as a cross-check, but `transform.rotation.z` read back from a matrix is wrapped to (−π, π].
- Then set the model value and start a new ramp from (θ(now), v(now)).

```swift
final class SpinController {
    let disc: CALayer                       // grooves + label sublayers; sheen is a SIBLING, not a child
    var period: CFTimeInterval = 1.8        // 33⅓ RPM in-app
    private var ω: Double { 2 * .pi / period }
    private var state = (t0: CACurrentMediaTime(), θ0: 0.0, v0: 0.0, v1: 0.0, τ: 0.0)

    private func angleAndVelocity(at t: CFTimeInterval) -> (Double, Double) {
        let dt = t - state.t0
        guard state.τ > 0, dt < state.τ else {         // steady (v1) after the ramp
            let ramp = state.τ * (state.v0 + state.v1) / 2
            return (state.θ0 + ramp + state.v1 * (dt - state.τ), state.v1)
        }
        let a = (state.v1 - state.v0) / state.τ
        return (state.θ0 + state.v0 * dt + 0.5 * a * dt * dt, state.v0 + a * dt)
    }

    func setPlaying(_ playing: Bool, rampUp: Double = 0.7, rampDown: Double = 1.0) {
        let now = CACurrentMediaTime()
        let (θ, v) = angleAndVelocity(at: now)
        let target = playing ? ω : 0
        let τ = (playing ? rampUp : rampDown) * abs(target - v) / ω   // partial ramps scale down
        state = (now, θ, v, target, τ)

        disc.removeAllAnimations()
        let end = θ + τ * (v + target) / 2
        CATransaction.begin(); CATransaction.setDisableActions(true)
        disc.setValue(end, forKeyPath: "transform.rotation.z")      // model = final ramp value
        CATransaction.commit()

        if τ > 0 {
            let ramp = CABasicAnimation(keyPath: "transform.rotation.z")
            ramp.fromValue = θ; ramp.toValue = end; ramp.duration = τ
            let k = (v + target) > 0 ? 2 * v / (v + target) : 0
            ramp.timingFunction = CAMediaTimingFunction(controlPoints: 1/3, Float(k/3), 2/3, Float((k+1)/3))
            ramp.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            disc.add(ramp, forKey: "ramp")
        }
        if playing {
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = end; spin.toValue = end + 2 * .pi
            spin.duration = period; spin.repeatCount = .infinity
            spin.beginTime = disc.convertTime(now, from: nil) + τ   // starts exactly when the ramp ends
            spin.isRemovedOnCompletion = false
            spin.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            disc.add(spin, forKey: "spin")
        }
    }
}
```

Notes:
- `transform.rotation.z` accepts unbounded angles, so the model value grows monotonically. Re-normalise it (θ mod 2π) only while static, to avoid precision drift after days of uptime (INFERRED).
- For a simple hard pause/resume (e.g. scene backgrounding), Apple's QA1673 recipe is enough: `speed = 0; timeOffset = convertTime(now)` / `speed = 1; beginTime = convertTime(now) − pausedTime` (VERIFIED).

### 3.3 Cross-fading the label on track change while spinning

Layer tree (all bitmaps pre-rendered once per track, off the main thread):

```
hostLayer (static)
├─ discLayer            ← rotates (the only animated layer)
│   ├─ groovesLayer     (static bitmap, radially symmetric, opaque-ish)
│   ├─ labelLayerA      (circle-cropped album art with alpha)
│   └─ labelLayerB      (incoming art, opacity 0→1)
├─ sheenLayer           ← STATIC specular highlight (screen/plus-lighter blend)
└─ tonearmLayer         ← static, or its own small rotation for "needle drop"
```

- Track change: set `labelLayerB.contents`, animate B opacity 0→1 and A 1→0 over 0.6–0.8 s, then swap roles.
  - Alternatively, `CATransition(type: .fade)` on a single label layer.
  - Both run in the render server *inside* the rotating parent, so rotation continues untouched (VERIFIED principle: sublayers inherit the parent's transform; Core Animation guide above).
- **Pre-crop the art to a circle in the bitmap** (alpha) instead of `cornerRadius`/`mask` on a rotating layer. Masks and shadows can force extra offscreen passes every frame (WWDC14 419 offscreen-rendering discussion, https://www.wwdcnotes.com/notes/wwdc14/419, INFERRED application).

### 3.4 Frame rate on ProMotion

- **Mechanism.** `CAAnimation.preferredFrameRateRange` (iOS 15+) is VERIFIED: https://developer.apple.com/documentation/quartzcore/caanimation/preferredframeraterange.md.
- **Default cap on iPhone.** Without `CADisableMinimumFrameDurationOnPhone` in Info.plist, iPhone ignores >60 Hz requests for CA animations and display links. That key "unlocks the full range" (Apple ProMotion doc as reported by iClarified, https://www.iclarified.com/82663/apple-posts-developer-documentation-for-promotion-on-iphone-13-pro-12-refresh-rates-used, VERIFIED secondary). **Do not add the key**; leaving it out means we are capped at 60 Hz by default.
- **Does 60 vs 120 matter?** No, for this content.
  - **Grooves are radially symmetric**, so rotating them is visually almost invariant. Perceived motion comes only from the **label art** (and any deliberate asymmetric groove detail).
  - Label radius ≈ 50 pt in a 300 pt disc. At 33⅓ RPM (200°/s) its rim moves ≈ 175 pt/s: **2.9 pt/frame at 60 fps**, 1.5 pt at 120. At 60 fps that is already below obvious judder for a rotating photo (INFERRED).
  - 120 Hz doubles composite work for no visible gain. Request `CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)`. In Low Power Mode, drop to `preferred: 30`.
- **Power.** ProMotion "adapts to onscreen content and so reduces its power consumption" (WWDC21 10147, https://developer.apple.com/videos/play/wwdc2021/10147/, VERIFIED). A 60 Hz request lets the panel run at 60 instead of 120.

### 3.5 Lifecycle, Reduce Motion, Low Power Mode

| Condition | Action | Source |
|---|---|---|
| View off-screen / `onDisappear` / scrolled away | `layer.speed = 0` (QA1673) or remove animations; resume analytically | QA1673 (VERIFIED) |
| `scenePhase != .active` (inactive or background) | Pause. Infinite CA animations are commonly **removed when the app backgrounds** even with `isRemovedOnCompletion = false`, so re-add on foreground from the analytic angle | Community: https://gist.github.com/cobysy/c8d37924a15d6b9d4007 and SO mirrors (INFERRED-supported). Our analytic model makes re-adding jump-free |
| Reduce Motion | **No continuous spin.** Static disc; track changes as a cross-fade. Apple lists "spinning, or vortex effects" among triggers to "disable or change", and for decorative motion suggests "stopping it entirely" | https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria (VERIFIED); `accessibilityReduceMotion` (https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion.md, VERIFIED) |
| Optional user override | Settings toggle "Spin even with Reduce Motion" (off by default), plus a "Spin speed" setting | Also satisfies "providing a control to allow the user to stop the motion" (same Apple page) |
| Low Power Mode | Cap at 30 fps, or stop spinning (user setting). Observe `NSProcessInfoPowerStateDidChange` | https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled.md (VERIFIED) |
| Always-On / `isLuminanceReduced` (widgets, StandBy, Live Activities) | Static | animating-data-updates doc (VERIFIED) |

---

## 4. Rotation speed

Facts:
- 33⅓ RPM = 1.8 s/rev (200°/s).
- 45 RPM = 1.333 s/rev (270°/s).
- 16⅔ RPM (3.6 s/rev) is a real historical speed (Seeburg background-music records; https://en.wikipedia.org/wiki/Phonograph_record, VERIFIED).

**Recommendation** (design judgement, INFERRED):

| Surface | Default | Options | Reasoning |
|---|---|---|---|
| App (large disc, 60 fps, user is looking at it) | **33⅓ RPM (1.8 s)** with 0.7 s spin-up / 1.0 s spin-down | 45 RPM ("single"), 16⅔ ("relaxed") | Authentic. At 60 fps the label moves ~3 pt/frame. Grooves don't strobe because they are symmetric |
| Home-screen widget (small, peripheral vision, unknown cadence) | **16⅔ RPM (3.6 s)** | 33⅓ "authentic" | (1) Unknown widget render cadence: if it is 20–30 fps, 200°/s means 7–10° steps per frame, visible stepping on a ~45 pt label; 100°/s halves that. (2) Constant fast motion in peripheral vision on the Home Screen is distracting and a vestibular trigger. (3) A real speed still makes for nice copy ("16⅔: Seeburg mode"). Revisit after measuring cadence on a device |
| Dynamic Island compact/minimal (if the effect works there) | 16⅔ or static | — | A 28 pt circle cannot show detail; slow is calmer |
| Reduce Motion on | **Static** everywhere | override toggle | Apple criteria above |

---

## 5. Layer composition for realism and low cost

**Principle.** Only one pre-rendered bitmap rotates. Everything that real vinyl keeps fixed relative to the light source stays **static on top**: the specular sheen, the anisotropic "light bar" across the grooves, and the tonearm. On real records the highlights stay put while the disc turns. That separation is what makes a flat image read as a spinning record, and it is also the cheap path.

- **Widget (`_ClockHandRotationEffect`).**
  - The effect is a `ViewModifier` applied to one child of a `ZStack`. Siblings are not affected (standard SwiftUI modifier scoping).
  - Apple's Clock widget and ClockHandKit's example rotate each hand independently over a static face (README usage `hourHand.clockHandRotationEffect(...)`, `minuteHand…`, VERIFIED).
  - GIF hacks stack many rotating, masked children in one widget (juejin articles, VERIFIED).
  - **Static overlay + rotating child is therefore confirmed to work.** The sheen should be a semi-transparent PNG with `.blendMode(.screen)` or `.plusLighter`. Blend modes inside widgets are expected to render, since they are standard SwiftUI (INFERRED; verify on device).
- **Bitmap prep (both surfaces).**
  - The app renders grooves + label into one square image at the exact pixel size of each widget family. Write it to the App Group container, and let the widget load it from disk.
  - Avoid live `clipShape`/`mask` on the rotating subtree: bake the circle into the alpha channel.
  - Keep widget images at roughly the widget's pixel size (e.g. ~510×510 px for a small widget @3x), since widget archives are size-limited (INFERRED; Agent 5 owns the exact limits).
- **App.**
  - Same tree as §3.3.
  - Optional realism: a very subtle 0.5–1 px eccentric wobble ("warp") via a second, slower animation on the disc's `position`. Keep it off by default (it is extra motion).
  - A shadow under the disc should be a **static** sibling bitmap, not `shadowPath` on the rotating layer.

---

## 6. Recommended architecture per surface

### Home-screen widget
- **Rendering:** a static `ZStack` with: rotating `[grooves + label]` disc → static sheen → static tonearm → optional `ProgressView(timerInterval:)` ring.
- **Rotation:** vendored ClockHandKit, `.custom(3.6)`, only when `entry.isPlaying && !reduceMotion && !isLuminanceReduced && !entry.lowPowerHint`.
- **Paused:** static `rotationEffect(phase(entry.date))`, `.transition(.opacity)`.
- **Track change:** new entry with the new label `.id(trackID)` and a 0.6 s opacity transition. The disc phase is unaffected because the angle is wall-clock driven.
- **Timeline:** `[now: playing] … [predictedEnd: stopped]`, so the disc stops by itself if no reload arrives.
- **Degradation:** if the private type is missing, ClockHandKit returns the plain view, giving a nice static vinyl. Add a debug-only overlay that reports "effect unavailable" by checking `_typeByName` once.

### Live Activity
- **Baseline (public):** static disc + art, track title, `Text(timerInterval:)` elapsed/remaining, `ProgressView(timerInterval:)`. Updates are ≤4 KB (ActivityKit doc, VERIFIED). Art must fit the presentation size, or "the system might fail to start the Live Activity" (VERIFIED).
- **Experiment:** apply the same ClockHandKit modifier in the Lock Screen and expanded presentations behind a feature flag. Record results on iOS 26.x and 27.x. Disable it in AOD / `isLuminanceReduced`.
- Note the doc tension:
  - The ActivityKit article says the system "ignores any animation modifiers" for Live Activities.
  - The WidgetKit animation article says iOS 17+ supports all built-in animations (≤2 s). Older-OS behaviour is "only … a subset".
  - The clock-hand effect is neither, so test it.

### Companion app
- SwiftUI shell with `UIViewRepresentable` → `VinylLayerView` (CALayer tree §3.3) and `SpinController` (§3.2).
- Inputs:
  - `isPlaying` and `trackID` from the playback model (Spotify state from other agents).
  - `scenePhase`, `accessibilityReduceMotion`, `isLowPowerModeEnabled`.
  - Visibility (`onAppear`/`onDisappear`).
- Frame rate 30–60 (preferred 60; 30 in LPM). Never 120.

---

## 7. Performance analysis (qualitative; measure in Phase 2)

| Surface | CPU (our process) | GPU / system | Wake-ups |
|---|---|---|---|
| Widget, spinning | **0**: the extension is not running ("WidgetKit renders the views on your behalf in a separate process … not continually active", keeping-a-widget-up-to-date, VERIFIED) | The system renderer re-composites the widget region each frame while visible (INFERRED; the same cost Apple accepts for its own Clock widget's sweeping hands) | None from animation. Reloads only for data. "The widget performs an animation" is one of the cases that doesn't count against the budget (VERIFIED) |
| Widget, paused | 0 | 0 (static) | — |
| App, steady spin (CA) | ~0 per frame (no main-thread callbacks) | Composite 3–5 layers at ≤60 Hz; one rotated ~900×900 px bitmap (≈3.2 MB RGBA) | — |
| App, TimelineView alternative | Small per-frame closure + diff on main | Same | 60 Hz |
| App, CADisplayLink alternative | Per-frame callback + CA commit | Same | 60 Hz main-thread wake-ups |

**Phase 2 measurement plan:**
- Instruments: Time Profiler + Core Animation FPS + Energy Log (or `MetricKit`).
- For the widget: a 60 fps screen recording to measure cadence, with a battery-drain A/B test (spinning vs static widget, 1 h, screen on). Compare total system CPU, not just our process (community note: load can shift to system processes; https://developer.apple.com/forums/thread/768768).

---

## 8. Risks and fallbacks (summary)

1. **The private effect stops working** (Medium–High per year).
   - Effect: static vinyl, already designed as the fallback.
   - Monitor the ClockHandKit and octree issue trackers after each iOS beta.
2. **Low Power Mode ticking or low cadence makes the widget look janky** (Medium).
   - Fix: slower default speed, or static when LPM is hinted.
3. **Pause/resume latency in the widget** (High, structural).
   - Fix: predicted-end stopped entries, cross-fades to mask jumps, an optional phase-offset Δ. This is not solvable with animation tech alone.
4. **App Review** (Medium, if ever submitted; N/A for sideloading).
   - Fix: ship a build flag to compile ClockHandKit out entirely.
5. **Toolchain** (Low).
   - ClockHandKit is source, Swift 6.2. Avoid octree's binary, which requires Xcode 26.0.1 and has had bitcode problems.

## 9. Confidence summary

| Claim | Confidence |
|---|---|
| Private WidgetKit effect exists and rotates continuously in Home-screen widgets on iOS 17–27 (with ClockHandKit on 26.1+) | **High** (multiple independent reports + source code) |
| Angle is wall-clock driven, so there is no reset on reloads or track changes | **Medium–High** (documented by the wrapper and implied by clock semantics; epoch for `.custom` needs calibration) |
| Static overlay + rotating child works | **High** |
| Works in Live Activities / Dynamic Island | **Unknown** |
| Works in StandBy | **Medium** (INFERRED) |
| Low Power Mode behaviour | **Low** (one anecdotal report) |
| Core Animation is the best in-app engine | **High** |

## Sources (primary first)
- Apple, Animating data updates in widgets and Live Activities: https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities.md
- Apple, Keeping a widget up to date: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date.md
- Apple, Displaying dynamic dates in widgets: https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates.md
- Apple, Displaying live data with Live Activities: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities.md
- Apple, App Review Guidelines 2.5.1 / 2.4.2: https://developer.apple.com/app-store/review/guidelines/
- Apple, Reduced Motion evaluation criteria: https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria
- Apple, accessibilityReduceMotion: https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion.md
- Apple, isLowPowerModeEnabled: https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled.md
- Apple, TimelineView: https://developer.apple.com/documentation/swiftui/timelineview.md · animation(minimumInterval:paused:): https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:).md
- Apple, CAAnimation.preferredFrameRateRange: https://developer.apple.com/documentation/quartzcore/caanimation/preferredframeraterange.md
- Apple, QA1673 Pausing/resuming layer animations: https://developer.apple.com/library/archive/qa/qa1673/_index.html
- Apple, Core Animation Programming Guide (basics): https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/CoreAnimation_guide/CoreAnimationBasics/CoreAnimationBasics.html
- WWDC23 10156 Explore SwiftUI animation: https://developer.apple.com/videos/play/wwdc2023/10156/
- WWDC21 10147 Optimize for variable refresh rate displays: https://developer.apple.com/videos/play/wwdc2021/10147/
- WWDC14 419 notes: https://www.wwdcnotes.com/notes/wwdc14/419
- Apple Developer Forums: https://developer.apple.com/forums/thread/720640 · https://developer.apple.com/forums/thread/757696 · https://developer.apple.com/forums/thread/767243 · https://developer.apple.com/forums/thread/826682 · https://developer.apple.com/forums/thread/768768
- ClockHandKit: https://github.com/giljihun/ClockHandKit · source https://raw.githubusercontent.com/giljihun/ClockHandKit/main/Sources/ClockHandKit/ClockHandRotationEffect.swift
- ClockHandRotationKit: https://github.com/octree/ClockHandRotationKit · issues #2, #5, #9, #10, #11, #13 (https://github.com/octree/ClockHandRotationKit/issues)
- CHRK fork: https://github.com/b5nt/CHRK
- Bryce Bostwick WidgetAnimation: https://github.com/brycebostwick/WidgetAnimation · video summary https://youtubesummary.com/summary/NdJ_y1c_j_I · Hackaday https://hackaday.com/2025/05/17/animated-widgets-on-apple-devices-via-a-neat-backdoor
- juejin GIF-widget articles: https://juejin.cn/post/7399984522093838363 · https://juejin.cn/post/7426696679247347766
- The Tech Pulse: https://blog.andreszenteno.com/notes/apples-widget-backdoor
- David Smith, smooth clock hands: https://www.david-smith.org/blog/2023/11/06/design-notes-46/
- MD Vinyl App Store listing: https://apps.apple.com/us/app/id1606306441 · Product Hunt https://www.producthunt.com/posts/md-vinyl
- Scripting app widget animation docs: https://scriptingapp.github.io/guide/Widget/Animation%20for%20Widget%20and%20LiveActivity
- bannzai/cat-walk #39 (iOS 27 test plan): https://github.com/bannzai/cat-walk/issues/39
- Technics SL-1200M7L specs: https://www.technics.com/nz/products/dj-series/sl-1200m7l.specs.html · Stereophile: https://www.stereophile.com/content/technics-sl-1200gmesl-1210gme-turntable-specifications
- Phonograph record speeds: https://en.wikipedia.org/wiki/Phonograph_record
- iOS 27 release: https://macrumors.com/2026/09/13/ios-27-release-date-new-features/
- ProMotion doc coverage: https://www.iclarified.com/82663/apple-posts-developer-documentation-for-promotion-on-iphone-13-pro-12-refresh-rates-used
- CA background-resume workaround: https://gist.github.com/cobysy/c8d37924a15d6b9d4007
