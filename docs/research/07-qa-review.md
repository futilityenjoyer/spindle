# 07: QA and integration review of FEASIBILITY.md

Author: Agent 7 (QA and Integration). Date: 2026-11-11. This is an adversarial review. I did not edit FEASIBILITY.md or reports 01–06.

**Method.** I read FEASIBILITY.md and all six reports in full and traced each load-bearing claim back to its report and confidence label. I spot-checked five claims against primary sources (§5) and simulated the proposed widget timeline policy with a short script.

**Severity scale**
- **Blocker:** the architecture as written fails a core user requirement. Fix it before Phase 2 starts.
- **Major:** a wrong or overstated claim, an unresolved conflict, or an undefined behaviour for a required scenario. Fix it in the document before M1.
- **Minor:** wording, citation, or a small omission.

---

## 1. Summary of findings

| ID | Severity | FEASIBILITY.md section | One-line issue |
|---|---|---|---|
| B1 | **Blocker** | §4.2 "bounding staleness"; §2 Q4/Q5; §7.1 | The policy (stop at `trackEnd + 20 s`, reload at `max(trackEnd, now + 5 min)`) makes the widget **stop spinning while music plays** about half the time, and **show the previous track** about 60% of the time, during ordinary uninterrupted listening |
| M1 | Major | §4.2, §7.1 | The timeline policy for paused, idle (204) and error states is not defined. Reports 01, 02 and 05 disagree (15–30 min / 30–60 min / 60 min / `.never`), so the "resume" behaviour is undefined |
| M2 | Major | §4.4 widget row, §6 | Low Power Mode is missing from the widget. Report 04 has evidence that clock-hand rotation **ticks** in LPM, and reports 04 and 05 both recommend a static disc |
| M3 | Major | §2 Q1, §4.1, §10 | ClockHandKit has never been reported working when built with **Xcode 26.6** (the CI default) and run on **iOS 27**. The iOS 27 evidence is one user building with Xcode 27.0, plus the package author |
| M4 | Major | §3, §4, §7 | Missing artwork, offline, Spotify closed, ads, and the "stale" state are not defined in FEASIBILITY. Report 03 defines them, but its 3-minute stale threshold conflicts with the timeline design |
| M5 | Major | §2 Q4/Q5, §4.2 | "Instantly in the app" is overstated. App Remote connects only if Spotify is running and playing, and community reports say it drops about 30 s after a pause. No reconnect or poll policy is defined, so a resume inside the app can go unseen |
| M6 | Major | §4.1 widget row, §5 row 3, §6 | The widget makes a Web API call on **every** reload. That includes app-triggered reloads and every widget instance, which breaks the "0 Web API calls in app" budget. Report 05's 60-second freshness check is missing |
| M7 | Major | §4.3, §5 row 2 | Using the App Group as a keychain access group is **supported by Apple** (spot-checked), but it is stated as fact for re-signed builds. The plan omits the accessibility class and the before-first-unlock error path, which matters for the restart scenario |
| M8 | Major | §7.6, §10 | No behaviour or warning is defined for a missed 7-day re-sign. The app and widget stop silently |
| M9 | Major | §3 row 3, §4.1, §7.1 vs report 03 §5 | The plan's main fix for staleness is a widget refresh or play/pause **button**. Report 03's wireframes have no such button, and its tap target opens Spotify. Buttons are also inactive while the phone is locked |
| M10 | Major | §3 "Low battery usage", §6 | The battery section omits Apple DTS's warning that the rotation hack "can cause battery drain". It also drops report 05's user setting to turn the widget spin off. "✅ Achievable" reads like a claim |
| M11 | Major | §1, §2 Q9, §8 | The verdict says "no unavoidable cost" while Q9 lists Spotify Premium as an unavoidable cost. Premium's price is not given, and the free and paid columns are mixed |
| m1–m15 | Minor | various | See §3 |

---

## 2. Blocker and Major issues

### B1 (Blocker): the "bounding staleness" timeline stops the record during normal playback

**Where:** §4.2 (sequence diagram and "Key design idea: bounding staleness"); §2 Q4 ("normal listening stays in sync"); §2 Q5; §7.1.

**What's wrong**

1. **The stop entry and the reload floor work against each other.**
   - Each reload emits *spinning now*, then *stopped/unknown at `trackEnd + 20 s`*.
   - The next reload is requested at `.after(max(trackEnd, now + 5 min))`.
   - For any track with less than about 4 min 40 s left at reload time, the stop entry fires **before** the next reload. That covers almost every reload, because the average track is about 3.5 min (reports 02 and 05).
   - The record therefore stops, and keeps showing the finished track, until the next reload, even though Spotify is still playing.
2. **Simulated effect.** Script in the scratchpad: back-to-back tracks, with every reload honoured exactly at the 5-minute floor (the best case, before any budget exhaustion).

   | Tracks | Record spinning while music plays | Widget shows the wrong (previous) track | Reloads in 3 h |
   |---|---|---|---|
   | 3.5 min fixed | **47.5 %** | **59 %** | 36 |
   | 2.5–5 min random | **43 %** | **64 %** | 36 |

   - The disc is stopped more than half the time during ordinary listening.
   - After the 40–70/day budget runs out, which takes about 3–6 h by §7.1's own estimate, reloads become sparse and the record stays stopped for most of the session.
   - This is the inverse of the requirement "vinyl stops when paused". Here it stops when **not** paused. Report 03 §1 says false or stale states are exactly what users criticise in MD Vinyl and TikWidget.
3. **"Normal listening stays in sync" (§2 Q4) is false** under the 5-minute floor that §7.1 itself asserts. A new track appears only at the next reload, which is up to 5 min after it starts.
4. **The 20 s grace is unsourced.**
   - Report 04 §1.7 puts the stop entry *at* the predicted end.
   - Report 05 §1.4 puts it at **`trackEnd + 10 min`**, specifically so the disc does not stop on a merely late reload.
   - Report 02 uses +2 s, and report 01 uses +5 s, but both of those are for the *reload policy*, not a stop entry.
   - The synthesis picked a value none of them proposed, and the worst one of the three stop-entry options.
5. **"Adding timeline entries is free" is stated as fact. No report verifies it.**
   - What is verified is that the *budget* counts reloads (01 Q2, 05 §1.1).
   - Apple's guidance is that "timeline entries … at least about 5 minutes apart" (spot-checked, §5). A stop entry 30 s–4 min after `now` breaks that guidance.
   - Whether WidgetKit renders such an entry on time is **INFERRED / device test**, not settled.
6. **"Consistent with report 01?"** Only partly.
   - Report 01 supports the general shape: a multi-entry timeline, `.after(date)`, and an entry that changes appearance.
   - It also warns against dense timelines (Q1.4).
   - It says the budget runs out after 2–4 h of track-end reloads (candidate architecture, item 3), and it proposes `/me/player/queue` to predict the next tracks *without* a reload.
   - The synthesis dropped that last mitigation.

**Proposed fix: replace the "Key design idea" paragraph in §4.2 with:**

> **Key design idea: predict, then bound.**
> - Each reload makes **one radio burst**: `currently-playing`, plus `GET /me/player/queue` if it is available in Development Mode (verify in M1; report 01 proposed it and report 02 did not verify it).
> - From that response, the widget builds a timeline that **advances the label at each predicted track boundary** up to the next reload date. Entries cost no budget, but entries closer than about 5 min apart go against Apple's guidance, so the M4 device test must confirm they render on time.
> - The final entry is a **"last seen" state at `nextReload + grace`**, where `nextReload = max(trackEnd, now + 5 min)`.
> - In that state the disc stops, and the caption shows `Text(lastFetch, style: .relative)`.
> - Start the grace at 2 min and tune it in M4 (report 05 used 10 min).
> - If the queue endpoint is unavailable, keep spinning with the current label until `nextReload + grace`. Accept a stale *label* rather than a false *stop*.
> - Worst case after a pause in Spotify: the disc keeps spinning for up to `max(remaining track, 5 min) + grace`, unless the user taps refresh or opens the app.
> - Worst case after the budget runs out: the disc stops and shows "last seen" honestly.

Also make these changes:
- **§2 Q4:** replace "so normal listening stays in sync" with "so the widget catches up at most about 5 minutes (one reload interval) after a track change. With queue prediction it shows the right track during uninterrupted listening."
- **Feasibility matrix:** add a row "Widget correctness during continuous listening: ⚠️ device-test (M4)".
- **M4 exit criteria:** add "3 h continuous-listening run: % time the widget shows the correct track and the correct spin state, logged by Diagnostics."

---

### M1 (Major): paused, idle and error timeline policy is undefined

**Where:** §4.2 shows only the playing policy. §7.1 covers pause/skip latency but not *resume*.

**Evidence:** the reports disagree, and the synthesis doesn't pick one.

| Report | Paused / idle policy |
|---|---|
| 01 (candidate architecture) | `.after(+30–60 min)` or `.never` |
| 02 §7.1 | `.after(now + 15–30 min)` or `.never` with an app-driven reload |
| 05 §1.4 | `.after(now + 60 min)`, `.never` after 2 h paused; errors: `.after(+30 min)` or `Retry-After` |

The choice decides scenario 4 (resume). With `.never`, a resume in Spotify is **never** shown in the widget until the user taps it or opens the app.

**Fix:** add a "Timeline policy by state" table to §4.2.

| State | Entries | Policy |
|---|---|---|
| Playing | per B1 | `.after(max(trackEnd, now + 5 min))` |
| Paused | static disc at the frozen angle, "Paused" | `.after(now + 30 min)` for the first 2 h, then `.after(now + 2 h)` (not `.never`, so a resume is eventually seen) |
| Idle (204 / `item` null) | idle disc | `.after(now + 60 min)` |
| Offline / 5xx / timeout | last snapshot marked "last seen" | `.after(now + 30 min)` |
| 429 | last snapshot | `.after(max(now + 30 min, Retry-After))`; on `QUOTA_EXCEEDED`, a 24 h cooldown flag (02 §7.1) |
| 401 refresh failed / `invalid_grant` | Reconnect state | `.never` (the app reloads after sign-in) |

Also state in §7.1: "A **resume** in Spotify reaches the widget at the next paused-state reload (up to 30 min), or immediately on a refresh tap or app open."

---

### M2 (Major): no Low Power Mode behaviour for the widget

**Where:** §4.4 widget row ("Off under Reduce Motion / Always-On / `isLuminanceReduced`"); §6 "Widget animation" row; §9 M5 ("LPM/thermal handling").

**Evidence**
- Report 04 §1.5 and §1.8: Apple's own clock-hand rendering "ticks" in Low Power Mode (octree #11, 2025-11-09; I confirmed this comment in the spot check).
  - At 1 Hz, 16⅔ RPM means 100° jumps per tick, and 33⅓ RPM means 200° jumps.
  - Report 04 recommends a static disc when LPM is hinted.
- Report 05 §5 table: Low Power Mode → **static disc**, with a policy floor of **15 min**.
- FEASIBILITY covers LPM only for the app (30 fps).
- The user listed Low Power Mode as a required test scenario.

**Fix**
- Change the §4.4 widget row to: "Off under Reduce Motion, Always-On / `isLuminanceReduced`, **and Low Power Mode** (`ProcessInfo.isLowPowerModeEnabled` read at timeline time, best-effort, because LPM changes don't trigger a reload) and thermal state ≥ `.serious`."
- Add to §6: "LPM: widget static, playing-state reload floor raised to 15 min (05 §5). Whether WidgetKit itself shrinks the budget in LPM is undocumented. Measure it with the reload log."
- Note that if LPM is turned on mid-timeline, the disc may tick until the next reload. This is a device-test item.

---

### M3 (Major): ClockHandKit has not been tested with the CI toolchain on iOS 27

**Where:** §2 Q1 ("works on iOS 26.1+ and 27 per community reports"); §4.1; §4.6 (CI = `macos-26`, Xcode 26.6 default per 06); §10.

**Evidence**
- Report 04 §1.4 table: ClockHandKit is shown working only for:
  - **Xcode 26.1 → iOS 26.1+** (README demo), and
  - **Xcode 27.0 → iOS 27** (one user report).
- Spot check (§5):
  - The ClockHandKit README claims "Xcode 26.1 or later" and **does not mention iOS 27 or `honorIdealizedDate`**.
  - octree #11 has exactly two iOS 27 statements, both dated 2026-10-03: the package author, and one user ("Tested in Xcode 27.0 and released on iOS 27").
- Report 04 §1.4 infers that Apple's breakage was a **linked-on-or-after (SDK-keyed) gate**. So the build SDK matters, not just the runtime.
- Our pipeline builds with **Xcode 26.6 (iOS 26.6 SDK)**. Nobody has reported Xcode 26.6 SDK → iOS 27 runtime.
- Report 06 says an `xcode-27` runner image exists only in **preview**, and the `macos-26` image has **no iOS 27 simulator runtime** (26.2/26.4/26.5 only).
- Report 04 §1.10 rates toolchain risk "Low" without checking this pair.
- The fallback (a static disc) means this is not a Blocker. But it is the product's headline feature.

**Fix**
- Change §2 Q1 to: "…works on iOS 26.1+ (built with Xcode 26.1) and on iOS 27 (built with Xcode 27.0; one user report plus the author). **Our CI's Xcode 26.6 → iOS 27 pairing is untested.**"
- Add to **M0 exit criteria:** "Build ClockHandKit's example widget with Xcode 26.6 (`macos-26`) **and** with the `xcode-27` preview image, install both on the iOS 27 phone, record which spins, and pin that Xcode in CI."
- Add to §10: "Build-SDK / runtime pairing breaks the private effect | Medium | CI matrix (26.6 + 27.x), effect-availability probe shown in Diagnostics, static fallback."

---

### M4 (Major): required edge states are not defined in FEASIBILITY

**Where:** §3 (the "special cases" are only named), §4, §7. FEASIBILITY never mentions missing artwork, offline, Spotify closed, or ads.

**Evidence**
- Report 03 §5.9 and §6.6 define all of these: Missing art / local file → neutral label with ♪; Ad → neutral label with "Advertisement"; Offline; Nothing playing; Signed out; Stale.
- Report 05 §1.4 defines the error policy.
- Report 02 §3.1 defines the ad, podcast and local-file payloads.
- **Unresolved conflict 1: stale threshold.** Report 03 §5.9 wants a "Stale (last fetch > 3 min while playing)" state and asked Agents 1/2 to set the threshold (03 §9.1). The synthesis never answered.
  - With reloads at least 5 min apart, a 3-minute rule would mark the widget "Offline" for most of every interval.
- **Unresolved conflict 2: offline in the app.** Report 03 §6.6 says the app is offline → "disc spins down and stops".
  - But App Remote is local IPC with the Spotify app, and Spotify can play downloaded music offline.
  - So while App Remote is connected, the app still knows the true state offline. It should keep spinning.

**Fix:** add a §4.7 "Edge states" table that adopts report 03 §5.9 and §6.6 with two amendments:
1. **Stale** = "now > `nextReload + grace`" (from B1), not "fetch older than 3 min". Show the caption via `Text(date, style: .relative)` so it updates without reloads.
2. **App offline:** if App Remote is connected, trust it and keep spinning. Show "Offline" only when App Remote is down **and** the Web API fails.

Also add an artwork-failure row: "Art download fails or times out (8 s, report 05) → render with neutral label + ♪, don't block the timeline, retry on the next reload; never show the previous album's art for a new track."

---

### M5 (Major): "instantly in the app" is overstated, and in-app reconnect is undefined

**Where:** §2 Q4 and Q5 ("Instantly in the app"); §4.2 ("App Remote connect (only if Spotify running…)"); §5 row 3 ("Web API is called in-app only on foreground when App Remote can't connect").

**Evidence**
- 02 §1.4 (VERIFIED): `connect` needs Spotify running. The README FAQ says music must be **playing** to connect.
- 02 §1.4 (INFERRED): after a long pause Spotify is suspended and `connect` fails.
- 05 §4 (community report): the connection drops about 30 s after nothing is playing.
- **Consequence:** the app is open, the user pauses from Control Center (event received), Spotify suspends, App Remote drops, and the user resumes from Control Center. The app has no connection and no poll, so it **never sees the resume**.
- Report 02 §7.1 step 3 had a fallback: poll at the predicted track end, plus a 30 s keep-alive while visible, backing off to 60 s while paused. FEASIBILITY drops the cadence entirely.

**Fix**
- Change Q4/Q5 to: "**Instantly in the app while App Remote is connected** (Spotify running). Otherwise the app polls the Web API while visible (02 §7.1: track-end poll + 30 s keep-alive, 60 s while paused), so in-app latency is ≤ 30–60 s."
- Add to §4.2: "On `appRemoteDidDisconnect` while foreground → switch to visible-only polling, and retry `connect()` whenever a poll returns `is_playing == true`. Never call `authorizeAndPlayURI`."
- Add an M3 exit criterion: "pause, wait 2 min, resume from Control Center with the app open → reflected within 30 s."

---

### M6 (Major): the widget fetches on every reload, including app-triggered ones

**Where:**
- §4.1 widget row ("Timeline provider calls the Web API once per reload")
- §4.2 ("1 request per reload")
- §5 row 3 ("In-app uses App Remote events (0 Web API calls)")
- §6 network row

**Evidence**
- While the app is open, every App Remote track or pause change triggers `WidgetCenter.reloadTimelines`.
- As written, each of those reloads makes the widget call the Web API. That is about 17 calls per listening hour while the app is open, and it is multiplied by the number of widget instances, because the budget is per instance (01 Q2).
- Report 05 §1.4 and §8 rule 2 prevent this: "Read the App Group cache before any network call. If … state in the last 60 s, use it."
- Report 05 also requires a 2 s debounce of app reloads (§1.3 c).
- Report 01 notes the WWDC26 caveat that "frequent reloads while your app is in the foreground might be throttled".

**Fix:** change §4.1 widget row to:
> "Timeline provider **first reads the App Group snapshot; if it is < 60 s old (written by the app or another widget instance), it uses it without a network call**; otherwise one Web API burst."

In §4.2, change the app→widget arrow to "reloadTimelines (debounced 2 s; exempt from budget while foreground, may be throttled)".

---

### M7 (Major): App Group as keychain access group is plausible but stated as settled, and the restart path is unhandled

**Where:** §4.3 Token storage; §5 row 2; §4.1 diagram ("Keychain access group = App Group ID").

**Evidence**
- **Supported by Apple** (spot check, §5): "You can use app group names as keychain access group names, without adding them to the Keychain access groups entitlement", and "Xcode doesn't prepend the app group with the team identifier." Report 01 Q4 also says this (VERIFIED).
- **Survives re-signing: INFERRED, plausible.**
  - Report 06 §3.1 and §4.5 (VERIFIED from source): AltStore and SideStore sign each bundle with the *profile's* entitlements, which contain the rewritten `<group>.<TEAMID>`.
  - So the runtime-resolved group string should be a valid access group in both app and widget.
  - Sideloadly's group handling is undocumented (06).
  - FEASIBILITY marks this "**Device test** in M1" in §5 but states it as fact in §4.3 ("so the app and widget share it even after re-signing").
- **Two omissions**
  1. **Accessibility class.** Report 02 §2.5 specifies `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` "because widgets reload while the device is locked". FEASIBILITY leaves it out. With the default class (`WhenUnlocked`), widget reloads while the phone is locked fail.
  2. **Restart scenario.** After a reboot and before the first unlock, both the Keychain item (AfterFirstUnlock) and the fallback file (`CompleteUntilFirstUserAuthentication`) are unreadable.
     - `SecItemCopyMatching` then returns `errSecInteractionNotAllowed`, not "item not found".
     - If the code treats that as "no token", the widget shows "Connect Spotify". Worse, a careless implementation could clear `needs_reauth` state or tokens. (Reviewer inference, standard iOS keychain behaviour; device test.)
- **Re-signer change.** Moving between Sideloadly and SideStore, or changing the Apple ID or team, changes the group string. The tokens become unreachable, and the user has to log in again. This is not stated.
- Report 06 §4.6 explicitly recommended *not* sharing tokens. The synthesis overrides that, which is acceptable because the widget-fetch architecture needs it. It should say so.

**Fix:** replace the §4.3 Token storage bullets with:
> - **Token storage:** Keychain item with `kSecAttrAccessGroup` = the runtime-resolved App Group ID (Apple documents app-group names as valid keychain access groups; that this survives AltStore/SideStore re-signing is INFERRED from report 06's source reading; **device test in M1**). Accessibility: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.
> - **Before first unlock** (after a restart) the read returns `errSecInteractionNotAllowed`. Treat it as "temporarily unavailable": render the last snapshot from the archived timeline, use `.after(now + 15 min)`, and **never** clear tokens or show "Reconnect" on this error.
> - **Fallback:** an App Group file with `NSFileProtectionCompleteUntilFirstUserAuthentication` (same before-unlock rule).
> - Changing re-signer, Apple ID or team changes the group ID, so it requires one re-login. Diagnostics shows the resolved group.

---

### M8 (Major): a missed 7-day re-sign silently breaks everything

**Where:** §7.6, §8, §10 (no row).

**Evidence**
- 06 §4.2 (VERIFIED): apps must be re-signed within 7 days, "or they stop launching".
- Report 01 C4: "the widget and app stop working until reinstalled".
- Auto-refresh depends on:
  - **Sideloadly:** the PC being on, on the same Wi-Fi, with iTunes Wi-Fi sync and the phone screen on.
  - **SideStore:** LocalDevVPN plus Wi-Fi.
- What the widget shows after expiry is undefined. It could be blank, or the last archived entry, possibly still spinning. This is reviewer inference; test it.

**Fix**
- Add to §4.1 companion app: "Diagnostics reads `ExpirationDate` from `embedded.mobileprovision` (06 §4.6 already parses this file) and shows 'Signature expires in N days'. The app and widget show a small warning badge at ≤ 2 days."
- Add a §10 row: "Missed re-sign → app and widget dead | Medium (weekly) | expiry badge; SideStore on-device refresh as primary; Sideloadly daemon as backup."
- Add an M6 test: "let the signature expire; record the widget's appearance; re-sign; confirm the App Group data and tokens survived."

---

### M9 (Major): the refresh/play-pause button is missing from the design and has limits that aren't stated

**Where:**
- §3 row "Playback detection" ("unbudgeted tap-to-refresh / play-pause button")
- §4.1 widget row
- §7.1 ("Tapping the widget's refresh or play/pause button updates it immediately")
- §1 ("when you tap it")

**Evidence**
- Intent-triggered reloads **are** unbudgeted and guaranteed. This is VERIFIED in 01 Q2 and 05 §1.1, and I spot-checked Apple's text: "The widget performs an app intent, such as when the user taps a button…"
- That claim is fine. The problems are these:
  1. **Report 03 has no such button.** Its small Record, small Sleeve and medium wireframes (§5.2–5.4) have no refresh or play/pause control, and the whole-widget tap (`widgetURL`) **opens Spotify** (03 §5.2, Spotify link-back rule). This conflict between 03 and 01/05 is missing from FEASIBILITY §5. As a result, §1's "when you tap it" would open Spotify, not refresh.
  2. **Locked phone:** "buttons and toggles are inactive until the user authenticates" (01 Q2, VERIFIED). The fix doesn't work from the Lock Screen or StandBy while locked.
  3. **Play/pause** needs `user-modify-playback-state` (02 §2.3). Adding that scope later forces a re-login. It also returns 403 for Free users (02 §4).
     - Reviewer inference, not in any report: `PUT /me/player/pause|play` can fail with "no active device" if the Spotify app has been suspended a long time. Test this in M4.

**Fix**
- Add a §5 row: "Widget design has no refresh control; widget tap opens Spotify (03) vs architecture relies on an intent button (01/05) → resolution: small widgets get a 28 pt refresh/play-pause `Button(intent:)` in the bottom-left status slot; the art/disc area keeps the Spotify deep link; medium gets both. 03 to update wireframes."
- Change §1 "or when you tap it" to "or when you tap its refresh/play-pause button (not while the phone is locked)".
- Request `user-modify-playback-state` at first login so adding the button later doesn't force a re-login.

---

### M10 (Major): the widget spin's battery risk is understated

**Where:** §3 "Low battery usage" ("✅ Achievable by design (**not yet measured**)"); §6 "Widget animation" row.

**Evidence**
- 04 §1.10 (VERIFIED): an Apple DTS engineer on this exact hack said "not supported by the system and cannot be recommended … **Can cause battery drain**".
- 05 §3.1: whether the system caps the widget rotation's frame rate is **UNVERIFIED**, and the rotation may hold the display at a higher refresh rate (WWDC22). Report 05 recommended making spin "a user setting, including 'spin only when charging / not in Low Power Mode'".
- FEASIBILITY drops both points.
- The document does avoid a parity claim, which is good and meets the requirement. But "✅ Achievable" is a green tick for something unmeasured, with a known Apple warning against it.

**Fix**
- Change the matrix cell to: "⚠️ **Unknown until measured.** App and network design are low-cost; the widget spin's render cost is unmeasured and Apple DTS warns the technique 'can cause battery drain'."
- Add to §6: "Widget spin is a **user setting** (On / Only when charging / Off), default On for the M4 trial; the S1 'visible' A/B in the measurement plan decides the shipped default."

---

### M11 (Major): the cost verdict contradicts itself, and the free/paid split is unclear

**Where:** §1 ("feasible from Windows at **no unavoidable cost**, but only if you have Spotify Premium"); §2 Q9 ("Unavoidable costs? **Spotify Premium**"); §8 ("Your existing subscription").

**Evidence**
- Premium is an unavoidable recurring cost (02 §0.1, §4). It is "free" only if the user already pays for it. The reports never give its price.
- The user asked for costs separated into free and paid. §8 mixes required and optional items in one column.

**Fix**
- Change §1's first sentence to: "The product is **feasible from Windows. The only unavoidable cost is a Spotify Premium subscription** (Spotify's 2026 Development Mode rule); if you already have Premium, the marginal cost is $0."
- Split §8 into two tables:
  - **"Required"**: Spotify Premium (price not researched; varies by country), plus the free items.
  - **"Optional paid"**: Apple Developer Program at $99/yr; GitHub Pro if you want a private repo with more minutes; Codemagic overage. Each with what it buys.

---

## 3. Minor issues

| ID | Section | Issue | Fix |
|---|---|---|---|
| m1 | §7.1; §2 Q4 | "At least 5 minutes apart" is presented as a hard reload floor. Apple says "WidgetKit imposes a minimum amount of time before it reloads" (amount unspecified) and that **entries** should be "at least about 5 minutes apart" (spot-checked). Report 05 §0.1 overstated this as VERIFIED, and FEASIBILITY inherited it. Also, "after heavy use … iOS spaces reloads 15–60 minutes apart" misreads Apple, who give 15–60 min as the *typical average* over the day. What happens after the budget runs out is **undocumented** (spot-checked). | "Reloads are typically ≥ ~5 min apart (Apple's entry-spacing guidance; the exact floor is undocumented). Apple's 40–70/day budget averages one reload every 15–60 min; behaviour after exhaustion is undocumented; measure in M4." |
| m2 | §3 Windows row | "Iteration loop ~6–10 min". Report 06 §1.1 says 8–15 min per job (INFERRED). | Use "~8–15 min (06, INFERRED)". |
| m3 | §0 correction | "We target **iOS 18.0+**" appears in no report: 01 says 26 (or 17), 04 says the floor is 17, 05 says 26, 06's draft says 17.0. The likely reason, `widgetAccentedRenderingMode` (iOS 18), isn't stated. CI has no iOS 18 or iOS 27 simulator runtimes (06), so iOS 18 would ship untested. | Either target **iOS 26.0** (one user on iOS 27; 01 and 05 agree), or keep 18.0, state the reason, and add "iOS 18–25 untested". |
| m4 | §4.5 | "Spotify's 300 px image only" conflicts with 02 §1.2 (App Remote `fetchImage` ~600 px in-app, no network) and with 03 §3.1: the medium Sleeve art is 126 pt, which is 378 px at 3x, and StandBy scales small widgets up (01 Q4). The ~718k px archive pixel-area limit (01, 05) is also omitted. | "In-app: App Remote `fetchImage` at the exact label pixel size. Widget: 300 px Web API image; use 640 px only for sleeves > 100 pt. All entry images ≤ family pixel size and < ~700k px." |
| m5 | §5 row 4 | Mis-cited. Report 03 offers 33⅓/45 RPM, not 16⅔, and its default widget is **still**. Report 05 §3.1 says 33⅓ for the widget; the 16⅔ default comes from 04 only. Report 03's spin curves (exponential lag / drag) can't be expressed with 04's linear-ramp `CABasicAnimation` Bezier, so the implementer needs a keyframe or an approximation. The app-engine conflict (03 §3.5 suggests `TimelineView`/`CADisplayLink`; 04 and 05 say Core Animation) isn't listed. | Re-cite as "04 vs 03/05". Add "spin curves: approximate 03's 0.65 s / 1.6 s with 04's ramp math or a `CAKeyframeAnimation`". Add the engine row. |
| m6 | §4.1 SDK row | "SPM binary package, no vendoring" (06) is presented as settled, but 02 R8 says "vendor the xcframework" and cites SPM identity clash #465. | List it as a conflict. Resolution: SPM, with vendoring as the fallback if #465 bites. |
| m7 | §2 Q8; §3 install row | Q8 says "Unsigned `.ipa`", but §4.6 ad-hoc signs it. "App Group IDs rewritten by re-signers" is true for AltStore and SideStore; Sideloadly is undocumented (06). Two details are left out: SideStore occupies 1 of the 3 app slots, and Codemagic's 500 free minutes are for personal accounts only. | Make the wording exact. |
| m8 | §4.2 diagram | "On resign-active → disconnect App Remote, stop animation" leaves out the **final `reloadTimelines` before disconnect**, which both WWDC26 (01 Q2) and 05 §4 recommend. | Add "write snapshot + one final reload, then disconnect". |
| m9 | §4.5, §7.4 | Spotify Terms items are missing: the cache must not keep content "indefinitely". Report 02 §5.3 says evict after about 7 days and on sign-out. The logo attribution and link-back (02 §5.2, 03 §2) are also not mentioned, and the app-name rule (03 §2.1) is missing. | Add an age limit (7 days) and a purge on sign-out to the LRU. Add an "Attribution" line to §4.4 or §4.7. |
| m10 | §10 | Several iOS 27 points are missing. When CI moves to the Xcode 27 SDK, "apps built with the latest SDK must use the scene-based life cycle or they fail to launch" (01 §0, VERIFIED). SwiftUI `App` is fine, but the auth callback must use `onOpenURL` / scene URL contexts, not `AppDelegate`. MetricKit: `MetricManager` is iOS 27+ and `MXMetricManager` is deprecated (05). | Add a low-likelihood risk row and a MetricKit note. |
| m11 | §2 Q9 | "since 2026-02-11". The reports cite a 2026-02-06 blog post and "Feb and Mar 2026" (01). 2026-02-11 appears only in 02's open question about new Client IDs. Whether the owner counts toward the 5 users is unknown (02 Q9.8; the quota page doesn't say, spot-checked). | "Since February 2026 (new Client IDs; existing apps from March 2026)". Add "confirm the owner allowlists themselves" to M1. |
| m12 | §4.3 | The scope list adds `user-modify-playback-state` "only with the play/pause widget button", but M4 includes the button. Adding a scope later forces a re-login. | Request it from M1 (see M9). |
| m13 | §4.1, §4.5 | Leaves out 05's 8 s request timeout and "no retries inside one timeline build". Also leaves out 03's **bundled fallback disc assets**, so a first-run widget is never blank. | Add both. |
| m14 | §2 Q8 | Report 01 Q7 says it is unknown whether the Developer Mode toggle appears on a phone never paired to a Mac. Reports 06 and 01 say the sideload tools pair over usbmuxd. Low risk. | Add "verify Developer Mode appears after the first Windows pairing" to M0. |
| m15 | §6 network row | "≤ budget (≤ ~70/day)" ignores unbudgeted intent reloads and app reloads, and multiple widget instances. | "≤ ~70 budgeted reloads per widget instance, plus user-initiated taps; the M6 freshness check stops duplicate fetches." |

---

## 4. Coverage of the user's requirements

| Requirement | Covered? | Notes |
|---|---|---|
| Spotify Free vs Premium documented | Partly | Q10 is correct. Free-user UI (disabled play/pause, ads) is only in 03 and 02. See M4, M9, M11. |
| Vinyl stops when paused | App yes; widget **no** | See B1, M1, M5. |
| Resumes smoothly | App yes (phase-continuous); widget visual yes (≤2 s fade) but detection undefined | See M1, M5. |
| No jump on track change | Yes | Wall-clock angle (04 §1.6, Medium–High confidence) plus label cross-fade. The epoch must be calibrated (04 §1.8). |
| Missing-artwork handling | **No** (in 03 only) | See M4. |
| Battery analysis without claiming parity | Mostly | No parity claim (good). The green tick and the omitted DTS warning are in M10. |
| Windows-only workflow | Yes | |
| Install without a Mac | Yes | m14 |
| Costs separated free vs paid | Partly | See M11. |
| Live Activity decision justified | Yes | It is justified by 01 Q5 and 05 §4: no network, stale without push, duplicates Spotify's Now Playing, 2 s cap. Deferral is sound. |
| 12 test scenarios | Partly | See the table below. |

### 4.1 Expected behaviour per scenario (derived from the architecture)

"Defined?" means defined in FEASIBILITY.md itself. "(rpt)" means defined only in a report. **UNDEFINED** means no source defines it.

| # | Scenario | Companion app (foreground) | Widget | Defined? | Gap / issue |
|---|---|---|---|---|---|
| 1 | Playback start | Spotify running and playing, so App Remote connects and the disc spins up in 0.65 s. If Spotify isn't running, it shows an "Open Spotify" button and never auto-plays (02 §1.4). | Shown at the next reload (budgeted, ≥ ~5 min, or a paused-state reload), or immediately on tap or app open. Then label plus spin. | Partly | The paused/idle reload cadence is undefined (**M1**). The "Open Spotify" state is only in reports. |
| 2 | Track change | `playerStateDidChange` → 450 ms art cross-fade, rotation continuous. Widget reload (debounced). | Label changes at the next reload. As written, the disc **stops at `trackEnd + 20 s`** until then. | Yes, but defective | **B1** (false stop, wrong track about 60% of the time). **M6** (duplicate fetch). |
| 3 | Pause | Instant event → 1.6 s spin-down, *if App Remote is connected*. | Keeps spinning until `trackEnd + 20 s`, the next reload, or a tap. Then a static frozen angle. | Yes | Bounded as claimed. The app-side caveat is in **M5**. |
| 4 | Resume | Instant if still connected. If Spotify suspended during the pause, **not detected** (no poll defined). | Detected only at the next paused-state reload (policy **undefined**) or on tap. Then a ≤2 s fade into the spin. | **UNDEFINED** | **M1**, **M5** |
| 5 | Spotify closed (force-quit) | App Remote disconnects. Fallback behaviour undefined in FEASIBILITY. 02/03: "Open Spotify" button, Web API 204 → Idle. | Next reload → 204 or `is_playing=false` → Idle/Paused state (03 §5.9). The disc may spin until `trackEnd + 20 s`. | (rpt) | **M4**, **M5**. The 204 behaviour is INFERRED (02 §3.1). |
| 6 | Offline | If App Remote is connected, the app is still correct (local IPC). 03 says spin down, which conflicts. | Fetch fails → **UNDEFINED** in FEASIBILITY. 05: keep the last entry marked stale, `.after(+30 min)`. The stop entry from the last good timeline still stops the disc. | (rpt) / conflict | **M4**, **M1** |
| 7 | Artwork fails | App: App Remote image API or cache. | **UNDEFINED** in FEASIBILITY. 03: neutral label + ♪. Must not block the timeline. | (rpt) | **M4** |
| 8 | App terminated | Nothing runs. App Remote is gone. | Unaffected: it runs on its own timeline and Web API calls. The last foreground snapshot is reused if fresh. | Yes, implicitly | m8 (final reload before backgrounding) |
| 9 | iPhone restart | — | Before first unlock, Keychain and App Group files are unreadable. The widget must keep its last snapshot and must not show "Reconnect". After unlock, it recovers at the next reload. Spin phase is wall-clock, so no reset. | **UNDEFINED** | **M7** |
| 10 | Widget removed / re-added | — | The new instance has its own budget (01). `getTimeline` → fresh fetch (or a < 60 s cache hit), then the correct state. Phase identical (wall-clock). Bundled fallback disc if the cache is empty (03). | Implicit | m13 |
| 11 | Low Power Mode | 30 fps cap; optional static (04, 05). | **UNDEFINED** in FEASIBILITY. 04 and 05: static disc and a 15 min floor. Without handling, expect **1 Hz ticking** (100°/tick at 16⅔ RPM). | App yes / widget **no** | **M2** |
| 12 | Free vs Premium | Owner must be Premium, or everything returns 403 (error screen). A Free *user* (allowlisted second account) gets read-only App Remote. In-app play/pause is partial (02 §4). Ads → "Advertisement" label (03). | Free user: refresh works; play/pause returns 403, so disable the button (03 §6.2). Ads → neutral label. | Partly | **M9**, **M11**. Testing Free needs a **second Spotify account** added to the allowlist (≤5 users). Add this to M6. |

Scenarios with **undefined** behaviour: **4 (Resume), 6 (Offline, widget), 7 (Artwork fails), 9 (iPhone restart), 11 (Low Power Mode, widget)**. Scenario **2 (Track change)** is defined but fails the requirement as designed (B1).

---

## 5. Primary-source spot checks (5)

| # | Claim | Source checked | Result |
|---|---|---|---|
| 1 | 5-minute spacing; 40–70/day budget; intent reloads unbudgeted | Apple, *Keeping a widget up to date* (DocC JSON) | **Intents:** confirmed ("The widget performs an app intent, such as when the user taps a button…"). **Budget:** 40–70 confirmed, described as a typical rate. **5 min:** stated for *entries* ("at least about 5 minutes apart"), with an unspecified minimum for reloads. **After exhaustion:** not documented. Supports m1 and B1.5. |
| 2 | Keychain access group = App Group ID | Apple, *Sharing access to keychain items among a collection of apps* | **Confirmed:** "You can use app group names as keychain access group names, without adding them to the Keychain access groups entitlement"; no team prefix; iOS 8+. That it survives re-signing remains INFERRED (M7). |
| 3 | Premium-owner rule | Spotify, *Quota modes* | **Confirmed:** "The app owner must have a Spotify Premium account for apps in development mode to function." Up to 5 users. Whether the owner counts is not stated. No date on that page (m11). |
| 4 | ClockHandKit works on iOS 27 | ClockHandKit README; octree #11 comments | The README says "Xcode 26.1 or later" and doesn't mention iOS 27. The iOS 27 evidence is the author plus one user on **Xcode 27.0** (2026-10-03). I also confirmed the LPM "ticking" comment (2025-11-09). Supports M2 and M3. |
| 5 | GitHub Free $12 credit; public repos free; macOS $0.062/min | GitHub Docs, Actions billing | **Confirmed** on all three. The ~190 min / ~20 builds arithmetic follows from it. |

Cost figures in §8 otherwise match report 06. The exceptions are m2 (build time) and m7 (Codemagic is personal accounts only).

---

## 6. Conflicts between reports: status

| Conflict | In FEASIBILITY §5? | Assessment |
|---|---|---|
| 03 vs 04: static widget vs private spin | Yes | Resolved well. |
| 02 vs 06: Keychain sharing | Yes | Resolved reasonably. Needs the M7 additions. |
| 02 vs 05: request rates | Yes | Resolution is fine, but the claim "0 Web API in app" is undermined by **M6**. |
| 04 vs 03: inertia and RPM | Yes | Mis-cited (m5). |
| Live Activity | Yes | Fine. |
| **Stop-entry timing: 04 (at end) vs 05 (+10 min); synthesis invented +20 s** | **No** | **B1** |
| **Paused/idle policy: 01 vs 02 vs 05** | **No** | **M1** |
| **03 stale threshold (3 min) vs ≥5 min reloads** | **No** | **M4** |
| **03 offline "spin down" vs App Remote working offline** | **No** | **M4** |
| **03 has no widget button + `widgetURL` → Spotify vs 01/05 intent button** | **No** | **M9** |
| **02 (600 px App Remote art) vs 05 (300 px) vs 03 sleeve sizes** | **No** | m4 |
| **02 (vendor SDK) vs 06 (SPM)** | **No** | m6 |
| **Deployment target: 01/05 (26) vs 04/06 (17) vs FEASIBILITY (18)** | **No** | m3 |
| **03 in-app engine (`TimelineView`/`CADisplayLink`) vs 04/05 (Core Animation)** | **No** (resolved silently) | m5 |
| **01 (17 reloads/h, budget gone in 2–4 h) vs 05 (≤12/h, about 3 h)** | **No** | Harmless. FEASIBILITY's "3–6 h" fits 05. State the basis. |

---

## 7. Verdict

**The core conclusion holds. The architecture document is not ready to approve as written.**

- The overall verdict survives review and is well sourced:
  - feasible from Windows;
  - Premium is mandatory;
  - the widget spin depends on a fragile private effect with a static fallback;
  - freshness, not animation, is the weak point;
  - no Live Activity in v1.
- Citations and confidence carry over faithfully in most places.
- The cost figures and the Premium-owner rule check out against primary sources.

The widget data model does not survive:
- The "bounding staleness" idea, the document's headline design contribution, makes the record **stop while music is playing** about half the time in ordinary listening (**B1**).
- Five of the twelve required scenarios have **no defined widget or app behaviour** (M1, M2, M4, M5, M7).
- The one feature that justifies the private API, ClockHandKit on iOS 27, has **never been tested with the CI's Xcode 26.6** (M3).

**Required before Phase 2:**
1. Fix B1.
2. Add the state-policy table (M1) and the edge-state table (M4).
3. Add the M3 spike to M0.
4. Apply the wording fixes for M5–M11.

None of these changes the product decision. They are document and design changes that take about a day, after which the plan can be approved.
