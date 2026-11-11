# 01: iOS Architecture Research (WidgetKit, ActivityKit, background execution, provisioning)

Author: Agent 1 (iOS Architecture Specialist). Date: 2026-11-11. Phase 1: research only, no app code.

Legend:
- **[VERIFIED]**: I read the cited source, and the claim paraphrases or quotes it.
- **[INFERRED]**: my reasoning from verified facts, or from secondary or community sources. Treat as a hypothesis to test on device.

Apple's DocC pages render client-side. I read most of them through their JSON twins (`https://developer.apple.com/tutorials/data/documentation/<path>.json`), which hold the same text as the human URLs cited below.

---

## 0. Platform-version correction (read first)

The brief says "current iOS is iOS 26.x". Apple's own documentation says otherwise:

- Apple's "Updates" hub is headed **"The 27 platform releases – June 2026"** and covers Xcode 27 and iOS 27. [VERIFIED] https://developer.apple.com/documentation/updates
- WWDC26 session 277, "WidgetKit foundations", says: "New in macOS, iOS, and iPadOS 27, the system extra large portrait family is now available." [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/277/
- WWDC26 session 223, "Live Activities essentials", says: "In iOS 27, Live Activities are visible in the Dynamic Island, when in portrait and landscape." [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/223/
- iOS 27 adds a new **Now Playing** framework, availability iOS 27.0. [VERIFIED] https://developer.apple.com/documentation/nowplaying

**Conclusion:** iOS 27.x is very likely the shipping OS today. iOS 26 is still the important baseline, because it introduced WidgetKit push and Liquid Glass widget appearances. Target **iOS 26 minimum** (or 17 for the interactive and animated widget baseline), build with the current SDK, and keep in mind that "**Starting in iOS 27, apps built with the latest SDK must use the scene-based life cycle or they fail to launch**". [VERIFIED] https://developer.apple.com/documentation/updates. A SwiftUI `App` already uses the scene-based life cycle. [INFERRED]

The WidgetKit and ActivityKit "updates" pages list nothing newer than June 2025. [VERIFIED] https://developer.apple.com/documentation/updates/widgetkit , https://developer.apple.com/documentation/updates/activitykit . For this project, iOS 27 brings no new widget animation capability that I could find. [INFERRED from absence]

---

## Q1. WidgetKit rendering model and what animation is possible

### Why widgets cannot run arbitrary continuous animation
- "WidgetKit renders the views on your behalf in a separate process. As a result, your widget extension is not continually active, even if the widget is onscreen." [VERIFIED] https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
- "Based on your timeline entries, the system archives a view representation and only renders the views using these representations when applicable… the system can't run your code or update data bindings at the time it renders your widget." [VERIFIED] https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities
- WWDC26: "Widget views are archived and rendered by the system, so your code isn't running while the widget is on screen." [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/277/
- HIG: widgets "don't support continuous, real-time updates". [VERIFIED] https://developer.apple.com/design/human-interface-guidelines/widgets
- A `Text` timer "becomes horizontally flexible… Widgets can't perform layout again after the system archives them". This confirms that layout and views are frozen at archive time. [VERIFIED] https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:)

Consequence: SwiftUI `TimelineView(.animation)`, `withAnimation(.repeatForever)`, `Canvas` with time, and `onAppear` do not produce continuous motion in a widget. A DTS engineer: "OnAppear isn't really valid for Widgets… The views themselves are archived". [VERIFIED, forum] https://developer.apple.com/forums/thread/773785

### What IS possible (public API)
1. **Transitions between timeline entries (iOS 17+).** Widgets animate data changes with default or custom SwiftUI animations and transitions: `transition(_:)`, `contentTransition(_:)` (for example `.numericText()`), `animation(_:value:)`, and built-ins such as `opacity`, `move(edge:)`, `slide`, `push(from:)`. **"Animations in widgets and Live Activities have a maximum duration of two seconds."** "In earlier OS versions, widgets don't animate". [VERIFIED] https://developer.apple.com/documentation/widgetkit/animating-data-updates-in-widgets-and-live-activities. The HIG repeats "a duration of up to two seconds". [VERIFIED] https://developer.apple.com/design/human-interface-guidelines/widgets
   - With the Always-On display, "the system doesn't perform animations to preserve battery life"; check `isLuminanceReduced`. [VERIFIED] same page.
   - `Transaction` isn't available to widgets. [VERIFIED] same page.
   - Per the brief, a 2-second entry transition does **not** count as rotation.
2. **System-driven dynamic dates (update live without reloads):** `Text(date, style: .relative/.offset/.timer/.date/.time)`, `Text(start...end)`, `Text(timerInterval:pauseTime:countsDown:showsHours:)`, and `ProgressView(timerInterval:countsDown:)`. "The progress view fills in automatically as time passes". [VERIFIED] https://developer.apple.com/documentation/widgetkit/displaying-dynamic-dates
   - Date-relative progress views "don't support custom styles". [VERIFIED] https://developer.apple.com/documentation/swiftui/progressview/init(timerinterval:countsdown:label:currentvaluelabel:)
   - So a continuously filling track-progress bar or ring and an elapsed or remaining time label are the **only public, genuinely continuous** widget visuals. A built-in circular style (as opposed to a custom one) may work. [INFERRED, test on device]
   - Apple explicitly suggests this for media: show "playback progress or a countdown without reloading at all". [VERIFIED] https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date
3. **Animations don't cost budget:** reloads aren't counted when "The widget performs an animation". [VERIFIED] keeping-a-widget-up-to-date.
4. **"Frame-by-frame" timelines** (many entries, each with a rotation angle) work against Apple guidance: "Your timeline provider should create timeline entries that are at least about 5 minutes apart." [VERIFIED] keeping-a-widget-up-to-date. A DTS engineer also said "You get 10MB of space per timeline". [VERIFIED, forum] https://developer.apple.com/forums/thread/773785. Many entries that each archive album art risk the archive and memory limits. **Not recommended.** [INFERRED]
5. **`_clockHandRotationEffect`:** it appears in my sources only as a private, underscored SwiftUI modifier used by community packages (for example ClockHandRotationKit, https://github.com/b5nt/CHRK) and Stack Overflow mirrors (https://kiwix.lema.org/stackoverflow.com_en_all_2023-11/questions/66258627/ios-clock-animations-on-homescreen-widget). It is **not** in Apple's public documentation. Agent 4 owns the deep dive. [VERIFIED that community sources reference it; not verified against Apple docs]

### iOS 27 "real-time widget updates with app open"
A WWDC26 word cloud mentioned this. An Apple Frameworks Engineer clarified: "There is way less delay now between successive updates in these scenarios. Think about mac window and widget visible together, or visionOS window and widget visible together". [VERIFIED, forum] https://developer.apple.com/forums/thread/834432. This shortens reload latency when the app and widget share the screen. It is **not** continuous animation, and it barely matters on iPhone. [INFERRED]

---

## Q2. Reload budget, exemptions, reload APIs, interactive widgets

### Budget [all VERIFIED: https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date]
- The budget is dynamic. It depends on how often and when the widget is visible, the last reload time, and "whether the widget's containing app is active".
- The budget is **per widget instance** and covers a 24-hour window tuned to the user's daily pattern.
- "For a widget the user frequently views, a daily budget typically includes from **40 to 70 refreshes**… roughly… every **15 to 60 minutes**". There is a learning period of a few days during which the widget may get more reloads.
- **Not counted against the budget:**
  - the containing app is in the foreground
  - the containing app has an active audio or navigation session
  - the containing app **is the current Now Playing app (MPNowPlayingInfoCenter)**
  - the widget performs an app intent (button or toggle)
  - the widget performs an animation
  - the locale changes
  - Dynamic Type or accessibility settings change
  - "In StandBy, the system refreshes your widget's display at a system-defined rate that doesn't count against its budget."
- WidgetKit may itself reload when a rarely visited page becomes visible, and may coalesce reloads.
- WWDC26 caveat: "frequent reloads while your app is in the foreground might be throttled. If your widget data may have changed a final call to reload when your app enters the background is usually a good idea." [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/277/
- A DTS engineer (Feb 2025) informally cited "72 refreshes per day". That number is not in the docs. [VERIFIED as forum statement] https://developer.apple.com/forums/thread/773785

**Critical for this product:** the Now Playing and audio-session exemptions apply to the **widget's containing app** only. Spotify is the Now Playing app, so our widget gets **no** exemption from Spotify's playback. [INFERRED from the wording "containing app", high confidence]

### Reload policies and APIs [VERIFIED, same page]
- `TimelineReloadPolicy`: `.atEnd` (the default), `.after(date)`, `.never`.
- From the app: `WidgetCenter.shared.reloadTimelines(ofKind:)`, `reloadAllTimelines()`, and `getCurrentConfigurations` to avoid needless reloads.
- WWDC26 restates the same three policies and reload through WidgetCenter or push. [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/277/

### Interactive widgets (iOS 17+) [VERIFIED: https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities]
- `Button(intent:)` and `Toggle(isOn:intent:)` are available in systemSmall, systemMedium, systemLarge, systemExtraLarge, systemExtraLargePortrait, and accessoryCircular and accessoryRectangular on iPhone and iPad.
- **Process:** "By default, the system runs the app intent in the same process as the widget extension. However, if the app intent's `openAppWhenRun` property is `true`, or if the intent conforms to `AudioPlaybackIntent`, `ForegroundContinuableIntent`, `LiveActivityIntent`, or `PushToTalkTransmissionIntent`, the system performs the app intent in the app's process."
- After `perform()` returns, "the system reloads the widget's timeline". "**Interactions with a toggle or button always guarantee a timeline reload.**" The budget page also says intent-triggered reloads are **not counted**.
- On a locked device, buttons and toggles are inactive until the user authenticates.
- **Design implication:** a "refresh", "play/pause" or "next" button gives an unbudgeted, guaranteed, user-driven refresh. It is battery-ideal. [INFERRED]

---

## Q3. WidgetKit push updates (iOS 26)

[All VERIFIED: https://developer.apple.com/documentation/widgetkit/updating-widgets-with-widgetkit-push-notifications , https://developer.apple.com/documentation/widgetkit/widgetpushhandler , https://developer.apple.com/documentation/updates/widgetkit]
- **The feature exists.** `WidgetPushHandler` (iOS 26.0+) has `pushTokenDidChange(_:widgets:)` and is attached with `.pushHandler(_:)` on the `WidgetConfiguration`. It was announced in June 2025.
- **Requirements:**
  - the Push Notifications capability
  - a remote notification server with a token-based APNs connection
  - headers `apns-push-type: widgets` and `apns-topic: <bundleID>.push-type.widgets`
  - body `{"aps":{"content-changed":true}}`
  - Broadcast channel push can't update widgets.
- **Budget:** "Like timeline updates, the system budgets WidgetKit push notifications and delivers them opportunistically… doesn't replace timeline updates." No numbers are published. On receipt, WidgetKit reloads timelines "similar to… reloadAllTimelines()".
- **Paid account required:** Push Notifications is **not** available to the free "Apple Developer" membership (see Q7). [VERIFIED] https://developer.apple.com/help/account/reference/supported-capabilities-ios
- Other requirements: a server (it would need to know the Spotify state, which means server-side polling of the Spotify Web API with the user's refresh token) and an APNs auth key, also from a paid account. [INFERRED]
- Community reports describe dropped or unreliable widget-push delivery on iOS 26, with no Apple answer. [VERIFIED as an unanswered report] https://developer.apple.com/forums/thread/839182
- **Verdict:** this is optional and depends on the paid account. Even then it is budgeted and opportunistic, so it is not a real-time track-change channel. [INFERRED]

---

## Q4. Widget extension constraints

| Topic | Finding | Status / Source |
|---|---|---|
| Memory | Widget extensions are jetsammed at **~30 MB** (`EXC_RESOURCE … limit=30 MB`). Apple doesn't document this. Reports run to Aug 2026, and a June 2026 question about raising it in iOS 27 got no answer. | VERIFIED as community and DTS-forum reports: https://developer.apple.com/forums/thread/713561 , https://developer.apple.com/forums/thread/842805 , https://developer.apple.com/forums/thread/834432 |
| Image size | Archival fails with "Widget archival failed due to image being too large… totalArea: 1048576 > max[718080]". The maximum pixel area varies by device and family. Downscale to display size before putting the image in the entry. | VERIFIED (forum): https://developer.apple.com/forums/thread/773785 |
| Timeline size | "You get 10MB of space per timeline" (DTS engineer). | VERIFIED (forum), same thread |
| Network | "Network requests are possible while the widget extension is active, such as when it provides a snapshot, or a new timeline." The request "may not have enough time to complete before the system halts the widget extension"; use background `URLSession` plus `onBackgroundURLSessionEvents(matching:_:)`. | VERIFIED: https://developer.apple.com/documentation/widgetkit/making-network-requests-in-a-widget-extension |
| App Group | Required for app-to-extension data: "you will need to use a shared container in an app group". | VERIFIED: https://developer.apple.com/videos/play/wwdc2026/277/ |
| Keychain sharing | App groups registered in your profile "also act as keychain access groups". Alternatively, use the Keychain Sharing capability (`keychain-access-groups`). Both are on the free tier (Q7). | VERIFIED: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups , https://developer.apple.com/documentation/security/sharing-access-to-keychain-items-among-a-collection-of-apps |
| Families | systemSmall/Medium/Large/ExtraLarge/ExtraLargePortrait; accessoryCircular/Rectangular/Inline (accessoryCorner is watchOS). systemExtraLargePortrait is new on iOS 27. | VERIFIED: https://developer.apple.com/documentation/widgetkit/widgetfamily , WWDC26 277 |
| StandBy / CarPlay | StandBy shows two **small** widgets side by side, scaled up, with the background removed. Mark the background removable. In low light the rendering is monochrome red (vibrant). | VERIFIED: https://developer.apple.com/design/human-interface-guidelines/widgets |
| Rendering modes | `fullColor` (Home Screen light and dark, StandBy, CarPlay); `accented` (Home Screen tinted or clear: background replaced with tint or Liquid Glass, content split into accent and primary groups and tinted white); `vibrant` (Lock Screen, StandBy at night: desaturated). Read `@Environment(\.widgetRenderingMode)`. | VERIFIED: HIG Widgets; https://developer.apple.com/documentation/swiftui/environmentvalues/widgetrenderingmode |
| Album art in tinted or clear mode | In accented mode the system "Tints opaque images with a single white color", so album art becomes a **white square** unless you opt out. Use `Image(...).widgetAccentedRenderingMode(.fullColor)` (iOS 18+); the options are `accented`, `accentedDesaturated`, `desaturated`, `fullColor`. Apple: "Reserve the fullColor rendering mode for images that represent media content, such as album artwork". HIG: "Consider reserving full-color images to represent media content, such as album art for a music app's widget, and use full-color images with smaller dimensions than the size of the widget." WWDC26 shows the white-rectangle failure with a book cover and fixes it with `.fullColor`. | VERIFIED: https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass , https://developer.apple.com/documentation/swiftui/image/widgetaccentedrenderingmode(_:) , HIG Widgets, WWDC26 277 |

Design consequence [INFERRED]:
- Keep the vinyl disc itself (grooves, sheen) as shapes and gradients that tint gracefully.
- Draw only the label-sized album art in `.fullColor`, which also matches the HIG's "smaller dimensions than the size of the widget".
- On the Lock Screen (vibrant), use a grayscale vinyl glyph plus text.

---

## Q5. Live Activities (ActivityKit)

[VERIFIED unless marked: https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities]

**Start and update paths**
- **Start:** "In general, your app needs to be in the foreground to start a Live Activity." A `LiveActivityIntent` can start one from the background (for example from a Control Center control). A push can also start one, which needs a paid account.
- **Update or end:** from the app with `activity.update(_:)`, "while it runs in the background — for example, by using Background Tasks", or with ActivityKit push.
- **The Live Activity itself:** "Each Live Activity runs in its own sandbox, and, unlike a widget, a Live Activity **can't access the network**". It cannot fetch Spotify itself.
- **LiveActivityIntent:** "When the system performs the intent, the system launches your app process without opening the app, performs the intent". [VERIFIED] https://developer.apple.com/documentation/appintents/liveactivityintent. The interactivity doc confirms that `LiveActivityIntent` runs in the app's process. Because ActivityKit's `update` is an app-process API, a `LiveActivityIntent` button in the Live Activity (or in a widget) can fetch Spotify state and call `activity.update`. [INFERRED from the two verified facts; test on device]

**Limits**
- **Duration:** up to **8 hours** active. After that it is removed from the Dynamic Island but stays on the Lock Screen up to 4 more hours, for a **12 h maximum**. After `end`, the default dismissal is up to 4 h, or `.immediate`, or `.after(date)`.
- **Payload:** static plus dynamic data, including updates and pushes, "can't exceed a combined size of **4 KB**". You cannot send album-art bytes in the state. Store the image in the App Group and pass a filename or ID. [INFERRED: the widget extension renders the Live Activity and can read the App Group container; test]
- **Images:** they must be "smaller or equal to the size of the presentation"; otherwise the system "might fail to start the Live Activity". StandBy scales the Lock Screen view 2x, so you need enough resolution. HIG margins: Lock Screen 14 pt; limited-width compact and minimal views fit "inside a 28pt-diameter circle" (iOS 27 landscape Dynamic Island). [VERIFIED: HIG Live Activities https://developer.apple.com/design/human-interface-guidelines/live-activities , WWDC26 223]
- **Presentations:** you must support compact, minimal, expanded and Lock Screen. StandBy uses the Lock Screen view at 2x. Live Activities also appear in CarPlay, the Mac menu bar and the Watch Smart Stack.

**Animation**
- Animations follow the same **2-second maximum** as widgets. The HIG says "Live Activities use system and custom animations with a maximum duration of two seconds".
- `Text` timers, `ProgressView(timerInterval:)` and `numericText` are supported.
- The Live Activity page still says "the system ignores any animation modifiers… and uses the system's animation timing". The animation page restricts that to "iOS 16 or earlier". These two Apple pages are inconsistent. [VERIFIED inconsistency]
- **A Live Activity therefore gives no continuous-rotation capability beyond what a widget has.** [INFERRED, high confidence]

**Update frequency**
- ActivityKit push has an hourly budget. Priority 5 doesn't count toward it; priority 10 does. `NSSupportsLiveActivitiesFrequentUpdates` is an **Info.plist key** (not an entitlement) that raises the push budget, and the user can turn it off. It applies only to push. [VERIFIED] https://developer.apple.com/documentation/activitykit/starting-and-updating-live-activities-with-activitykit-push-notifications , https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivitiesfrequentupdates
- Enabling Live Activities needs only the `NSSupportsLiveActivities` Info.plist key, with no capability or entitlement. [VERIFIED] https://developer.apple.com/documentation/bundleresources/information-property-list/nssupportsliveactivities

**HIG fit for "now playing"**
- In favor:
  - The HIG lists "music playback" among appropriate *interactive* controls.
  - The "transient" Live Activity style is exemplified by the Music app's AirPlay prompt. [VERIFIED] HIG Live Activities; displaying-live-data page.
- Against:
  - "Offer Live Activities for tasks and events that have a defined beginning and end… don't exceed eight hours."
  - "Update a Live Activity only when new content is available."
  - A personal listening session has no defined end. [VERIFIED quotes; INFERRED fit]
  - Spotify already publishes Now Playing info, which the system shows on the Lock Screen and in Control Center. [VERIFIED for the mechanism: https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter]
  - A second, duplicate activity competes for the Dynamic Island, where multiple activities go to the minimal or reduced-width presentation. [VERIFIED presentation behavior; INFERRED UX cost]
- **Without push** (that is, without a paid account and a server), our app cannot learn about track changes while it is suspended. The Live Activity would go **stale on every track change** unless the user taps an in-activity `LiveActivityIntent` refresh button or opens the app.
- **Verdict:** treat the Live Activity as an **optional, opt-in, user-started "listening session"** with `staleDate` set to the predicted track end. It is not core. It is acceptable for personal use (no App Review), but a weak experience without push. [INFERRED]

---

## Q6. Background execution for a non-media companion app

- **No continuous background:** DTS (Quinn): "How do I keep my app running continuously in the background? … **You can't.**" App refresh: "if you expect that the app refresh mechanism will grant you background execution time, say, every 15 minutes, you'll be disappointed… there are common scenarios where it won't grant you any background execution time at all!" [VERIFIED] https://developer.apple.com/forums/thread/685525
- **`BGAppRefreshTask`:** "The system decides the best time to launch your background task, and provides your app up to 30 seconds". It needs the `fetch` UIBackgroundModes value. [VERIFIED] https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app , https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask . It is useful only as an opportunistic top-up, for example to refresh widget data or end a stale Live Activity. [INFERRED]
- **Background push (`content-available`)** is rate-limited at more than 3 per hour and needs the paid push capability. [VERIFIED] same strategies page.
- **`BGContinuedProcessingTask` (iOS 26)** is for finishing user-initiated long jobs. It does not fit monitoring. [VERIFIED it exists] https://developer.apple.com/documentation/updates/backgroundtasks ; [INFERRED unsuitable]
- **Audio background mode:** App Review 2.5.4: "Multitasking apps may only use background services for their intended purposes: VoIP, audio playback, location, task completion, local notifications, etc." [VERIFIED] https://developer.apple.com/app-store/review/guidelines/ . A silent-audio keep-alive violates constraint B and the spirit of 2.5.4. Because Spotify holds the non-mixable audio session, it would also be fragile. **Rejected.** [INFERRED]
- **Reading Spotify's now-playing info locally is not possible:**
  - `MPNowPlayingInfoCenter` is "An object for **setting** the Now Playing information for media that **your app** plays". [VERIFIED] https://developer.apple.com/documentation/mediaplayer/mpnowplayinginfocenter . Community answers report `nowPlayingInfo` is nil for other apps' audio. [VERIFIED as community; INFERRED as fact] https://kaweah.freedombox.rocks/kiwix/content/stackoverflow.com_en_all_2023-11/questions/37198219/how-to-get-another-app-s-currently-playing-audio
  - `MPMusicPlayerController.systemMusicPlayer` "employs the built-in **Music app**", so it only sees Apple Music state. [VERIFIED] https://developer.apple.com/documentation/mediaplayer/mpmusicplayercontroller
  - The new iOS 27 **Now Playing** framework is publish-only: local sessions via `MediaSession` and remote sessions via `RemoteMediaSession`. It has no API to observe other apps. [VERIFIED for its scope; INFERRED absence of a read API from its topic list] https://developer.apple.com/documentation/nowplaying
- **So the only sanctioned data sources are Spotify's own:**
  - **Web API** `GET /me/player/currently-playing`, which needs network and an OAuth token.
  - **Spotify iOS SDK (App Remote)**, which talks to the Spotify app.
  - Many developers report that App Remote disconnects when our app is backgrounded or playback pauses. [VERIFIED as community reports] https://community.spotify.com/t5/Spotify-for-Developers/iOS-SDK-Disconnect-when-app-goes-to-background/m-p/5806965/highlight/true , https://github.com/spotify/ios-sdk . It is therefore **foreground-only** in practice, and the widget must use the Web API. [INFERRED]
- **Spotify policy risk:** since Feb and Mar 2026, Development Mode requires the owner to have **Premium** and allows at most **5 users** per app. The player endpoints were not removed. [VERIFIED] https://developer.spotify.com/documentation/web-api/tutorials/february-2026-migration-guide . This is outside Agent 1's scope, flagged for the Spotify agent.

---

## Q7. Free personal-team provisioning (sideload with a free Apple ID)

Apple's capability matrix. The "Apple Developer" column is the free tier: "No cost… developers can't distribute apps". [VERIFIED] https://developer.apple.com/help/account/reference/supported-capabilities-ios

| Capability | ADP (paid $99) | Free "Apple Developer" |
|---|---|---|
| App groups | Yes | **Yes** |
| Keychain sharing | Yes | **Yes** |
| Background modes | Yes | **Yes** |
| Data protection | Yes | **Yes** |
| Push notifications | Yes | **No** |
| Time Sensitive Notifications | Yes | No |
| Associated domains | Yes | No |
| Siri | Yes | No |
| iCloud (all) | Yes | No |
| Sign in with Apple | Yes | No |

WidgetKit extensions, Live Activities (an Info.plist key) and App Intents/interactive widgets are **not capabilities in the matrix**, so the free tier does not gate them. [INFERRED from their absence plus the Info.plist-only requirement]
- App Intents do not need the Siri capability. [INFERRED; App Intents aren't SiriKit; test]

**Consequences of no Push:**
- no WidgetKit push
- no ActivityKit push, whether to start or update Live Activities
- no background silent push

**Free-tier limits** [VERIFIED] https://developer.apple.com/support/compare-memberships/:
- "up to 10 App IDs, which expire after 7 days"
- 3 devices
- "up to 3 apps per device"
- profiles "expire 7 days from issuance". You must rebuild and reinstall.

The app plus the widget extension uses **2 App IDs**. Sideload tools register one App ID per app extension. [VERIFIED as AltStore FAQ] https://faq.altstore.io/altstore-classic/app-ids

**Developer Mode:** installing development-signed builds (such as an `.ipa`) needs Developer Mode on the device. Once it is on, "Developer settings appear on the device". [VERIFIED] https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device

**WidgetKit Developer Mode:** WWDC26: "Turn on WidgetKit developer mode while you're testing to lift constraints like reload budgets." [VERIFIED] https://developer.apple.com/videos/play/wwdc2026/277/ . The toggle is at Settings > Developer. [VERIFIED as forum answer] https://developer.apple.com/forums/thread/751386
- **Unknown:** whether that Developer pane appears on a device that was never paired to a Mac (Apple: Developer Mode "only appears… if you initiate pairing or if you previously paired the device to a Mac"). Sideload tools pair over usbmuxd from Windows, but this is untested.
- Lifting the budget conflicts with constraint B unless reload cadence is still self-limited. [INFERRED]

---

## Candidate architecture

```
                 +-------------------- iPhone ------------------------------------+
Spotify app ---- | (Spotify is the Now Playing app; we can't read it locally)       |
                 |                                                                |
                 |  Companion app (SwiftUI)                                       |
                 |   - OAuth PKCE with Spotify; tokens in shared Keychain group   |
                 |   - Foreground: Spotify iOS SDK App Remote (push-style         |
                 |     playerState callbacks) and/or Web API                      |
                 |   - Full-screen spinning vinyl: real continuous rotation       |
                 |     (TimelineView/.repeatForever), paused when not playing,    |
                 |     honours Reduce Motion / Low Power                          |
                 |   - On every track/state change while foreground:              |
                 |       write NowPlayingSnapshot.json + label.png (downsampled)  |
                 |       -> App Group container; reloadTimelines(ofKind:)         |
                 |     (unbudgeted in foreground; also one reload on              |
                 |     scenePhase -> background, per WWDC26)                      |
                 |   - Optional: BGAppRefreshTask (opportunistic top-up only)     |
                 |   - Optional: Live Activity "listening session" (opt-in)       |
                 |                                                                |
                 |  App Group container  (snapshot JSON, art PNGs, settings)      |
                 |                                                                |
                 |  Widget extension (separate process, ~30 MB)                   |
                 |   TimelineProvider.getTimeline:                                |
                 |     1. read snapshot from App Group                            |
                 |     2. if stale & token available: GET currently-playing       |
                 |        (background URLSession), download+downsample art        |
                 |     3. entry = track, artURL(file), progress, start/end dates  |
                 |     4. policy: playing -> .after(predicted track end + ~5 s)   |
                 |                paused/idle -> .after(+30-60 min) or .never     |
                 |   View: vinyl + full-colour label art, ProgressView(timer-     |
                 |     Interval:) / Text(timerInterval:) = continuous progress;   |
                 |     2 s transition between tracks; [Agent 4: clock-hand        |
                 |     rotation if viable]                                        |
                 |   Buttons (AppIntent, run in extension): Refresh / Play-Pause  |
                 |     / Next -> Spotify Web API -> write snapshot -> return      |
                 |     -> guaranteed, unbudgeted reload                           |
                 |   Live Activity UI (same extension, no network; reads App      |
                 |     Group art by filename from 4 KB ContentState)              |
                 +----------------------------------------------------------------+
   (Paid tier only)  Server: polls Spotify for the user -> APNs widgets push /
                     ActivityKit push. Adds a server, token custody and cost; still budgeted.
```

### What triggers widget reloads (battery-ordered)
1. **User taps a widget button.** This is guaranteed and unbudgeted. [VERIFIED]
2. **The app is in the foreground and detects a change.** This is unbudgeted, but frequent calls may be throttled. [VERIFIED]
3. **Timeline policy `.after(trackEnd)`** while playing. This is budgeted. At about 3.5 min per track it would use roughly 17 reloads per listening hour, so **the 40–70/day budget will run out after 2–4 hours of listening**, and the widget then shows the wrong track until the budget allows again. [INFERRED arithmetic from the VERIFIED budget]
   - Mitigations: use a coarser cadence such as `.after(max(trackEnd, now+15min))`. Optionally build multi-entry timelines from Spotify's queue endpoint (`GET /me/player/queue`) to predict the next tracks without reloading. This assumes no skips or pauses. Validating endpoint availability belongs to the Spotify agent.
4. **System-initiated reloads** (page becomes visible, StandBy). These are free. [VERIFIED]
5. **(Paid only) WidgetKit push from a server.** This is budgeted and opportunistic. [VERIFIED]

### Explicit compromises
- **C1. No truly continuous spinning in the widget with public API.**
  - The only continuous widget visuals are system date-driven `Text` and `ProgressView(timerInterval:)`.
  - The record "spins" only as 2-second transitions on entry changes, plus whatever Agent 4 finds viable for `_clockHandRotationEffect`. That modifier is private, so for a sideloaded personal app it carries App Store risk but no review risk.
  - True continuous rotation is guaranteed only **inside the companion app**.
- **C2. Track changes are eventually consistent.**
  - The widget can lag behind Spotify by up to the reload cadence, or longer after the budget runs out.
  - Skips and pauses made in Spotify are invisible until the next reload.
  - A "tap to refresh" affordance is the honest fix.
- **C3. The Live Activity is weak without push.**
  - Without a paid account and a server, it updates only when the app is in the foreground, on an opportunistic `BGAppRefreshTask`, or when the user taps a `LiveActivityIntent` button.
  - It is capped at 8 h, 4 KB of state, and image size.
  - It also duplicates Spotify's system Now Playing UI.
  - Make it opt-in, or defer it.
- **C4. Free account:** no push of any kind; re-sign every 7 days, after which the widget and app stop working until reinstalled; 2 of the 10 App IDs are consumed.
- **C5. The widget extension holds Spotify tokens.** The refresh token goes in the shared Keychain access group, which is allowed on the free tier. A token refresh happening in both the app and the extension needs a single-writer or lock strategy. [INFERRED]
- **C6. The ~30 MB memory ceiling and the archival pixel-area limit** mean album art must be downsampled before it goes into an entry. Ideally the app pre-renders the art at label size into the App Group, and the extension downsamples only on a cold path.

---

## Open questions
1. Does `ProgressView(timerInterval:)` render with the built-in **circular** style in a systemSmall widget on iOS 26/27 (a "groove progress ring")? Is it animated in StandBy and Always-On? Needs a device test.
2. Agent 4: is `_clockHandRotationEffect` still functional on iOS 26/27 widgets and Live Activities? What is its battery cost? Does it survive accented and vibrant rendering?
3. Does a widget `AppIntent` running in the extension have enough runtime for a Spotify Web API round-trip plus an art download before `perform()` returns? Apple documents no time limit. A fallback is to write the snapshot first and let `getTimeline` fetch.
4. Can a **widget** button use a `LiveActivityIntent` (which runs in the app process) to refresh both the widget and the Live Activity in one tap? Documentation implies yes; untested.
5. Can a Live Activity view load an image file from the App Group container? Common practice says yes; this is not stated verbatim in the docs I read.
6. Spotify (other agent):
   - Dev-mode limits (Premium owner, 5 users)
   - rate limits for per-reload polling
   - availability of `/me/player/queue`
   - App Remote background behavior on current SDKs
7. Signing and CI (other agent): can a free personal team sign on cloud macOS CI? The likely path is an unsigned CI build re-signed on Windows with a sideload tool. Do those tools correctly re-map App Group and keychain-group IDs for the widget extension?
8. Does the Settings > Developer pane, including "WidgetKit Developer Mode", appear on a device whose builds were installed only from Windows sideload tools? Should it be used at all, given the battery-first constraint?
9. Will the user's free or paid decision change? With $99 the architecture gains WidgetKit push and ActivityKit push, but it also needs a server that polls Spotify on the user's behalf, which is a new reliability, cost and security surface.
10. iOS 27 cleanup:
    - confirm the minimum deployment target (26 vs 27)
    - confirm that the systemExtraLargePortrait family on iPhone is worth supporting
    - confirm landscape Dynamic Island layouts if the Live Activity is kept
