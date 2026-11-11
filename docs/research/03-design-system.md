# 03 — Design System & UI/UX Spec (Phase 1)

**Owner:** Agent 3 (UI/UX & Visual Design) · **Date:** 2026-11-11 · **Target:** iOS 26 (Liquid Glass), WidgetKit + SwiftUI companion app
**Companion prototype:** `design/vinyl-prototype.html` (single self-contained file; open in Edge/Chrome on Windows)

Confidence tags: **VERIFIED** = read on the cited page during this research session. **INFERRED** = my reasoning, platform knowledge, or a secondary or summarised source. Check these before building on them.

---

## 0. Design direction in one paragraph

The design is a black lacquer disc on a quiet surface tinted from the album art. The grooves and the light on the disc never move. The only things that turn are the label and a few tiny run-out etchings, so the motion reads like a real platter under a fixed lamp and not like a spinning image. The album art is the only saturated colour on screen. It stays square, uncropped, with 4 pt corners and nothing drawn over it. By default it sits inscribed in a label whose surrounding colour is sampled from the art's own edge pixels, so the square appears to "bleed" into a circle without being cut. Widgets are calm, still objects: no tonearm, no blurred-art wallpaper, no gradients beyond a 1-step tonal tint. Motion is saved for the app and for short transitions on the widget.

---

## 1. Competitive study (brief)

| App | What it does visually | Praise | Criticism | Source / confidence |
|---|---|---|---|---|
| **MD Vinyl** (MD Studio / Hangzhou Midi Technology) | A virtual turntable with a draggable needle to seek. Widgets include a "Now Spinning" type combining album art with a spinning vinyl, plus record-player and radio widgets and extra-large sizes. Custom themes with colour picker, applied to widgets. Transparent widget backgrounds were added for desktop widgets. | "Coolest music app", "nothing is clunky", one-time purchase instead of a subscription | Widgets "glitchy": grey-out, show the previous song, don't update between songs. Few widget/record colours. Long ads, confusing paywall. Can't choose songs in-app. | VERIFIED: https://apps.apple.com/us/app/id1606306441 (summarised by fetch tool). Spotify added in v1.1 per developer comment: INFERRED (search summary of https://www.producthunt.com/posts/md-vinyl) |
| **VinylPod** | Spinning vinyl in a medium widget. Added a blurred background, a "cover art as wallpaper" option, custom colour, and a Liquid Glass refresh for iOS 26. | "runs super smoothly", "vintage modern look" | Vinyl widget only in **medium**. Wants more background control. Wallpaper bug. | VERIFIED: https://apps.apple.com/app/id6443989711 |
| **TikWidget** | Apple Music + Spotify now-playing widgets | Free, no limits | With Spotify, "songs ended before the widget showed them" (update lag) | INFERRED (search-result summary; listing https://apps.apple.com/app/id1556054655 not fetched) |

**Takeaways for us**
1. **Update freshness is what users judge the widget on.** Every competitor gets criticised for stale widgets. The design must make staleness honest (a "last seen" caption and a still disc when data is old) and never show a confident "Playing" state for an old track. **(Hand-off to Agent 1/2: refresh strategy.)**
2. **Offer small and medium from day one.** VinylPod is criticised for offering medium only.
3. **Customisation should be limited but meaningful.** Users ask for colours and record styles. We offer three label styles, two disc finishes (Black, Smoke), and the tint-from-art surface. That is enough for a personal app.
4. **Blurred-artwork backgrounds are common in this category, and we cannot use them** (Spotify forbids blurring artwork, see §2). That makes our flat art-tinted surface a distinguishing look.
5. **No tonearm in widgets.** At 158 pt a tonearm takes ~25 % of the area, competes with the art, and implies seek-by-needle, which Spotify discourages ("no indication that the user can seek"). We use no tonearm anywhere in v1.

**What we deliberately do not take from MD Vinyl:** turntable/plinth chrome, the needle-drop interaction, its record colourways, its "Now Spinning" naming, its full-circle art label as the default, its layouts, and its name.

---

## 2. Spotify branding and attribution constraints

Source: Spotify Design & Branding Guidelines, https://developer.spotify.com/documentation/design (**VERIFIED**). Spotify Developer Policy, https://developer.spotify.com/policy (**VERIFIED**).

### 2.1 Exact wording that affects the design

**Artwork**
- "The artwork must be kept in its original form, and its corners rounded according to the guidelines below."
- "Artwork must be kept in its original form. Don't animate or distort it in any way." (this rule includes "applying overlays and blurring")
- "Don't crop the artwork in any way."
- "Don't overlay images or text on top of the artwork." / "Don't cover the artwork with playback controls." / "Don't place your brand or logo on top of album artwork."
- "Artwork corners must be rounded to create optical blending with nearby UI elements." "Small & medium devices should use a 4px corner radius, whereas large devices should use a 8px corner radius."
- "If screen real estate is limited, it's OK to not include any album artwork."
- Playing views, DO: "Extract artwork color for background". The fetch summary also reported a fallback colour of #191414. **Re-check that hex value on the page.**

**Attribution and logo**
- "you must always attribute content from Spotify with the logo." "In partner integrations, you should always use our full logo (icon + wordmark)." "Use the icon on its own only if you do not have enough room for the full logo"
- "The Spotify logo should never be smaller than 70px in digital" / "The Spotify icon should never be smaller than 21px in digital"
- "The exclusion zone is equal to half the height of the icon"
- "The Spotify green logo should only be used on a black or white background". On a tinted surface, use the monochrome (white or black) logo.

**Linking**
- Metadata "must always link back to the Spotify Service". Link text: "OPEN SPOTIFY, PLAY ON SPOTIFY or LISTEN ON SPOTIFY" when Spotify is installed, otherwise "GET SPOTIFY FREE".
- Policy II.4.2: "Metadata, cover art and Audio Preview Clips must be accompanied by a link back to the applicable album."

**Metadata and controls**
- "The metadata must always be legible." "You may truncate metadata if space is limited. The user should always be able to view the entire metadata."
- "It is recommended that no play controls other than play/pause are provided in your app."
- "Make clear that the track progress bar is for information only - there should be no indication that the user can seek."
- "Podcasts need to have the option to seek 15 seconds forward or backwards."

**Naming**
- "The app name should not include 'Spotify' or be similar to 'Spotify' in sound or spelling." Policy VI.2: "the name should not begin with 'Spot'". "suggesting to users that it is 'for Spotify' is acceptable."
- "Your logo should not include, or look similar to the Spotify logo". Our app icon must not use green-on-black arcs.

### 2.2 The core conflict

A circular art label that spins **crops** the artwork and **animates** it, which breaks two explicit rules. A personal app that is never distributed carries less practical risk. But it still uses the Spotify Web API under the Developer Terms, so the team should design for compliance first.

### 2.3 Label treatment options

| Option | What it looks like | Crop | Animate | Overlay | Verdict |
|---|---|---|---|---|---|
| **A. Inscribed** *(recommended default)* | The full square art (4 pt corners) sits inside a circular label. The ring around it is filled with the **mean colour of the art's border pixels**, so it reads as the art continuing. A thin ring line sits at 0.968 r. No spindle hole is drawn over the art. The label rotates with the disc. | No | **Yes**: rotation is the only deviation | No | Compliance-leaning. The art is uncropped, undistorted, and has nothing drawn over it. It does rotate. |
| **B. Still** | Same as A, but the label stays upright and still. The disc body, run-out etchings and pressing irregularity turn underneath it. | No | No | No | **Compliant as written.** Physically wrong (real labels turn), but at small sizes it reads fine thanks to the etchings. Use this if you want zero deviation. |
| **C. Sleeve + Plain label** *(widget medium/small-sleeve default)* | The square art is shown as a still **sleeve** (4 pt corners). The disc slides out from behind it with a plain label in a colour taken from the art (Spotify DO: "extract artwork color"). | No | No | No | Fully compliant. This is the most "premium object" look. |
| **D. Full-bleed** | The art is cropped to a circle and fills the label, with a spindle hole on top. This is the classic look in the category. | **Yes** | **Yes** | **Yes** (hole) | **Non-compliant.** Offer only as an opt-in "Classic label" in Settings, with a one-line explanation. Never the default. |
| **E. Plain only** | Plain colour label with no art anywhere on the surface | — | — | — | Allowed ("OK to not include any album artwork") but loses the focal point. Use only for very small accessory sizes if needed. |

**Recommendation**
- **In-app Now Playing:** A (Inscribed). Settings → Label style offers Inscribed / Still / Classic (D, flagged).
- **Medium and Small-Sleeve widgets:** C. The art is the sleeve and the disc has a plain label.
- **Small Record widget:** A. On the widget the label is still anyway unless the experimental live spin is on (§5.1), so A is effectively B there.
- **Attribution everywhere:** full logo where ≥70 pt wide fits (medium, large, app). Icon only (21 pt) in the small widgets. Widget tap opens the current item in Spotify (deep link); see Agent 1/2 for the URL scheme.

The prototype has an "Inscribed / Still / Full-bleed / Plain" switch so the user can compare these.

---

## 3. Vinyl anatomy and rendering spec

### 3.1 Geometry (ratios of disc radius R)

```
                  ┌── rim / edge bevel          0.982 – 1.000 R   (bright bevel, AA edge)
                ┌─┴── lead-in (smooth land)     0.948 – 0.982 R   (1 faint guide groove)
              ┌─┴──── programme area            0.565 – 0.948 R   (fine grooves + 5 band gaps)
            ┌─┴────── run-out (smooth)          0.500 – 0.565 R   (locked groove at .547, etchings at .533)
          ┌─┴──────── label                     0.000 – 0.500 R   (deliberately ~1.5× real: art is the hero)
          │ spindle hole 0.024 R, spindle 0.015 R (Plain / Classic only; never drawn over art)
```

A real 12″ LP label is about 0.33 R. We use **0.50 R**, which is a 7″-single proportion, so the art stays readable. In the inscribed mode the art square side is `2r/√2 × 0.94 = 0.665 × label diameter`, and its corners touch 0.94 r.

| Surface | Disc | Label Ø | Inscribed art | Full-bleed art |
|---|---|---|---|---|
| Small widget "Record" | 120 pt | 60 pt | **40 pt** | 60 pt |
| Small widget "Sleeve" | 104 pt | 52 pt | (art on sleeve: **104 pt**) | — |
| Medium widget "Sleeve" | 126 pt | 63 pt | (art on sleeve: **126 pt**) | — |
| Large widget "Record" | 220 pt | 110 pt | 73 pt | 110 pt |
| In-app hero | 320 pt | 160 pt | **106 pt** | 160 pt |
| Lock Screen circular | 56 pt | 28 pt | 19 pt (mono) | — |

Note: 40 pt of art in the small Record widget is small. That is why we also ship the **Sleeve** small variant, which shows 104 pt of art. (INFERRED trade-off.)

### 3.2 Layer stack: what rotates and what does not

The key decision is that **concentric grooves are radially symmetric, so rotating them shows nothing.** Rotating a bitmap of fine rings at 200°/s only adds resampling shimmer and blur. So:

| # | Layer | Rotates? | Content |
|---|---|---|---|
| 1 | Contact shadow (light contexts only) | no | `y=1pt, blur=5pt, black 26 %` |
| 2 | **Disc base** (bitmap) | **no** | vinyl body, grooves, band gaps, run-out, lead-in, bevel |
| 3 | Pressing irregularity (bitmap) | yes | ±2–4.5 % low-frequency angular luminance variation, programme area only |
| 4 | Run-out etchings (vector) | yes | 9 short tangential dashes + 1 dash + 1 tiny triangle at 0.533 R, white 13 % |
| 5 | Label (bitmap per track) | yes (no in "Still") | per §2.3 |
| 6 | **Sheen** (bitmap) | **no** | anisotropic bow-tie highlight, masked to r > label |
| 7 | Spindle (vector) | no (symmetric) | Plain/Classic only |
| 8 | Rim hairline (dark contexts) | no | 1 px white 7 % at R − 0.5 px |

Because the sheen is modulated only by radius (groove phase and band gaps), it stays exactly aligned with the static grooves. That is physically right: the highlight comes from the light and viewer, not from the disc. The sheen never touches the label, so there is **no overlay on the artwork**.

### 3.3 Procedural parameters (verified visually in the prototype)

All luminance values are display-encoded (0–1) and the base tone is pure vinyl black. Use `pitch` in **device pixels** so ring density adapts to scale and never aliases.

| Parameter | Value | Notes |
|---|---|---|
| Base luminance | 0.046 (≈ #0B0B0D), RGB × (0.97, 0.98, 1.04) | slightly cool black |
| Groove pitch | `max(2.3 px, 1.05 pt × scale)` | about 1 visible ring per pt. **Ring count is derived, not fixed.** 158-pt small ≈ 25 rings @3x; 320-pt hero ≈ 60 rings @3x |
| Groove amplitude | 0.022 × (0.75 + 0.5·|loud(r)|) | sine in r |
| "Loudness" modulation | 1-D value noise, period ≈ 9 pitches, ±0.010 luminance | creates the banded look of real programme material |
| Band gaps (track separators) | 5 gaps, evenly spaced ±0.0175 R jitter (seeded) | gap width ≈ 1.6 pitch. Groove amp × 0.15, luminance −0.008. **In the sheen these gaps reflect 1.9×**, giving the classic bright separator lines |
| Programme edge fade | 2.5 pitches at each end | avoids hard ring at boundaries |
| Run-out | ±0.006 slow ripple, locked groove +0.024 at 0.547 R, −0.02 shadow just outside label edge | |
| Lead-in | +0.004, guide groove +0.016 at 0.960 R | |
| Bevel | +0.10 × sin(π·t), t across 0.982–1.0 R | bright edge; separates disc from dark backgrounds |
| Edge AA | coverage = clamp(R − r + 0.5, 0, 1) | |
| Sheen axis | −2.25 rad (upper-left ↔ lower-right) | bow-tie, both lobes |
| Sheen main lobe | 0.42 × |cos(θ−θL)|^(16+16·rn) × gloss | narrows outward |
| Sheen fill lobe | 0.10 × |cos(θ−θL−90°)|^34 × gloss | secondary light |
| Sheen wash | 0.03 × |cos|³ | broad |
| Gloss | programme: 0.5 + 0.5·(groove phase); gaps: 1.9; smooth zones: 1.25 | |
| Sheen colour / strength | rgb(238,242,255); ×1.15 colour, ×0.95 mono | |
| Irregularity | 0.65·sin(θ + 1.3·n(9rn))·(0.5+0.5·n₂(21rn)) + 0.35·sin(2θ + 2.4 + n₂(5rn)); white α 2.8 %, black α 4.5 % | rotation cue for the body |

**Light vs dark contexts.** The disc stays black in both. In light contexts, add the contact shadow (layer 1). In dark contexts, add the rim hairline (layer 8); the bevel does the rest. Do not lighten the vinyl for dark mode. A grey record looks cheap.

**Disc finishes (optional setting):** Black (above) and Smoke, which is a translucent dark tint: base 0.10 luminance at 85 % opacity over the surface tint. No coloured vinyl in v1, to keep the art as the only colour.

### 3.4 Mono / "glass" variant (tinted, clear, Lock Screen, StandBy night)

Same model, output as **white with α = clamp(0.05 + (v − 0.04)·4.4, 0, 0.85)**. In effect this is luminance-to-alpha baked at asset time, so we control it rather than relying on the system's desaturation. Grooves become faint etched lines, the bevel becomes a bright glass edge, and the sheen stays white. In Liquid Glass clear mode this produces an **etched-glass record**, which is the most native-feeling result (see prototype "Clear").

### 3.5 Pre-render and caching (for Agent 2 / implementation)

- Render layers 2, 3 and 6 **once per (diameter, scale, finish, variant)** with Core Graphics or a small Metal/`CIFilter` kernel. Each is about 1M px at 320 pt @3x, under 50 ms on device (INFERRED). Cache them as PNG in the **App Group** container keyed by `disc-{diam}@{scale}-{finish}-{color|mono}.png`.
- The widget extension **does not compute textures**. It loads the cached PNGs. Fall back to a bundled asset set for the 4 widget diameters at @2x and @3x, so a first-run widget never draws blank.
- Labels: compose per track (art + surround colour) at the label pixel size. Downsample art first: **≤ 2 × the display size** (e.g. 120 px label @3x → 360 px source). Widget-safe sizes keep memory well under the extension budget (INFERRED, about 30 MB).
- In-app rotation: drive with `TimelineView(.animation)` + `rotationEffect` on the label/irregularity group only, or a CALayer `transform.rotation` updated from a CADisplayLink. Physics are in §4.5. Never rotate the base or sheen image.

---

## 4. Design system

### 4.1 Colour tokens

**Neutral (fixed)**

| Token | Light | Dark | Use |
|---|---|---|---|
| `surface.base` | #F4F3F0 | #0E0E10 | app background when no art |
| `ink.primary` | rgba(17,17,19,.92) | rgba(255,255,255,.95) | titles |
| `ink.secondary` | rgba(17,17,19,.55) | rgba(255,255,255,.60) | artist, captions |
| `ink.tertiary` | rgba(17,17,19,.34) | rgba(255,255,255,.32) | disabled / hints |
| `fill.control` | rgba(0,0,0,.06) | rgba(255,255,255,.10) | icon buttons, play button |
| `fill.track` | rgba(0,0,0,.12) | rgba(255,255,255,.16) | progress track, hairline buttons |
| `vinyl.black` | #0B0B0D | #0B0B0D | disc base (never themed) |
| `vinyl.sheen` | rgb(238,242,255) | same | sheen layer |
| `status.stale` | systemOrange | systemOrange | "Offline · last seen" dot only |

**Art-derived (per track): "tint from art"**

Algorithm (Swift: `CGContext` draw to 24×24, then pure Swift):
1. Convert each pixel to **OKLCH**. Weight = `C^1.4 × (1 − 0.8·|L − 0.5|/0.5) + 0.002`. This favours colourful mid-tones and ignores near-black or near-white.
2. Build a weighted histogram of 24 hue bins (15° each). Take the max bin and its weighted mean hue `h` and chroma `C`.
3. **Edge colour** = mean RGB of the 92 border pixels (24×24 ring). This is used only for the Inscribed label surround.
4. Derive:

| Token | Formula (OKLCH) | Use |
|---|---|---|
| `tint.surface.dark` | L 0.20, C min(0.42·C, 0.045), h | widget/app background (dark) |
| `tint.surface.light` | L 0.94, C min(0.45·C, 0.035), h | widget/app background (light) |
| `tint.fill.dark/light` | L 0.30 / 0.86, C ≤ 0.035 | play button fill when tinted |
| `tint.accent.dark/light` | L 0.76 / 0.50, C clamp(C, 0.06, 0.14) | progress fill, selected states (sparingly) |
| `label.plain` | L 0.55, C clamp(0.85·C, 0.06, 0.16) | Plain label |
| `label.surround` | edge colour (unchanged) | Inscribed label ring |

5. **Contrast guard:** `ink.primary` on `tint.surface` must be ≥ 7:1 and `ink.secondary` ≥ 4.5:1. The L-values above guarantee this. If C is below 0.02 (greyscale art), use the neutral surface.
6. **Transition:** cross-fade surface colour over **600 ms ease-in-out** when the track changes.

Missing art falls back to neutral graphite (#2B2B30 dark / #D9D7D2 light label). Spotify suggests #191414 as a background fallback (re-check the value).

### 4.2 Typography (SF Pro; SF Pro Rounded for status and numerals)

| Surface | Element | Font | Size / weight / leading | Notes |
|---|---|---|---|---|
| Widget small | status ("Paused") | SF Pro Rounded | 11 / Semibold | Only when not playing. HIG minimum 11 pt (VERIFIED) |
| Widget medium | title | SF Pro Text | 15 / Semibold / 18.3, tracking −0.01 em, **2 lines** | truncate tail |
| | artist | SF Pro Text | 13 / Regular, 1 line | `ink.secondary` |
| | status | SF Pro Rounded | 11 / Semibold | with 9 pt glyph |
| Widget large | title / artist | SF Pro Text | 17 Semibold / 15 Regular | |
| | times | SF Pro Rounded | 11 / Medium, monospaced digits | |
| Accessory rect | title / artist | SF Pro Text | 13 Semibold / 13 Regular | system vibrant |
| App Now Playing | eyebrow ("PLAYING ON") | SF Pro Rounded | 10 / Semibold, +0.08 em, uppercase | |
| | title | SF Pro Display | 22 / Bold (≈ Title 2), −0.015 em | 1 line, marquee on long-press reveals full text (Spotify: full metadata must be viewable) |
| | artist | SF Pro Text | 17 / Regular (Body) | |
| | times | SF Pro Rounded | 12 / Medium, monospaced digits | |
| | link button | SF Pro Text | 12 / Bold, +0.09 em uppercase | "OPEN SPOTIFY" |
| App lists/settings | — | system text styles | Body / Subheadline / Footnote | full Dynamic Type |

Use text styles (`.title2`, `.body`, ...) in the app so Dynamic Type works. Widgets support Large to AX5 (HIG, VERIFIED), so medium titles must survive 2-line clamp at AX sizes; truncation is allowed.

### 4.3 Spacing and grid

- Scale: **4 · 8 · 12 · 16 · 20 · 24 · 32 · 48**.
- Widget margins: **16 pt standard, 11 pt tight** (HIG, VERIFIED). Small widgets use `.contentMarginsDisabled()` and apply 11 pt corner insets themselves. Medium/large keep the system 16 pt.
- App: 28 pt horizontal content inset on Now Playing (centres a 320 pt disc on 393 pt devices with 36.5 pt sides). 20 pt for lists.

### 4.4 Corner radii

| Element | Radius |
|---|---|
| Widget container | system (`containerBackground(for: .widget)`). Never hard-code; about 22–24 pt on current iPhones (INFERRED) |
| Content concentric to the container | `ContainerRelativeShape()` |
| **Album art (iPhone, all surfaces)** | **4 pt** (Spotify: small & medium devices 4 px). iPad: 8 pt |
| Buttons | capsule; icon buttons are circles (36 pt) |
| Cards in app (gallery, settings) | 20 pt continuous |

### 4.5 Motion

| Motion | Spec |
|---|---|
| Rotation speed | **33⅓ rpm = 200°/s** default (authentic). Setting: 33⅓ / 45 (270°/s) |
| Spin-up | first-order lag `ω += (ω₀ − ω)(1 − e^(−dt/0.22 s))` → 95 % in ≈ 0.65 s |
| Spin-down | drag `dω/dt = −(1.1·ω + 70°/s²)` → full stop ≈ 1.6 s, no overshoot |
| Track change | **label/sleeve cross-fade 450 ms** (cubic ease-in-out), **rotation untouched**. Text fades out 160 ms, swaps, fades in 220 ms. Surface tint 600 ms |
| Pause ↔ play icon | SF Symbols `.replace` content transition |
| Widget entry change | `.contentTransition(.interpolate)` for text. Optional "settle" of the label: +360° rotation, 1.2 s, ease-out (HIG allows animations up to 2 s, VERIFIED). Use it only on track change |
| Reduce Motion | no rotation at all, and no settle. Cross-fades only (150 ms) |
| Low Power Mode | rotation capped at 30 fps or paused when the app is backgrounded (INFERRED) |

---

## 5. Widgets

Reference sizes are for 393/390 pt-wide iPhones (HIG table, **VERIFIED**): small 158², medium 338×158, large 338×354, circular 72², rectangular 160×72. 375-pt devices use 155 / 329×155. All geometry below is defined as a ratio of the widget side so it scales.

### 5.1 About spinning on the Home Screen

- **Public API cannot keep a widget spinning continuously.** Widgets are snapshots. Updates are rationed. Dense timelines are unreliable (INFERRED from multiple community sources and Apple forum guidance, e.g. https://hackaday.com/2025/05/17/animated-widgets-on-apple-devices-via-a-neat-backdoor).
- **Default (v1):** the widget disc is still. The label is upright (0°), which also makes the art easiest to read. Liveness comes from the status line, the live progress (`ProgressView(timerInterval:)` on large/accessory), and the 1.2 s settle on track change.
- **Experimental (personal sideload builds only):** continuous rotation via the private `_clockHandRotationEffect` trick used by some apps (INFERRED: https://github.com/octree/ClockHandRotationKit). It would get an App Store build rejected and may break on any iOS update. Behind a debug flag. **Agent 2 decides.** The design works without it.

### 5.2 systemSmall: "Record" (default small)

```
┌──────────────── 158 × 158 ────────────────┐
│ 11                                         │
│        ╭───────────────────────╮           │   disc Ø120 (0.76 W), centred
│      ╭─╯  ░░ grooves (static)  ╰─╮         │   margins 19 all round
│     │     ╭───────────────╮      │         │
│     │     │  ┌─────────┐  │      │         │   label Ø60 (0.50 disc)
│     │     │  │ ART 40² │  │      │         │   art 40 pt, r4, inscribed
│     │     │  │   r4    │  │      │         │   label ring = art edge colour
│     │     │  └─────────┘  │      │         │
│     │     ╰───────────────╯      │         │
│      ╰─╮      sheen ⟋        ╭─╯           │
│        ╰───────────────────────╯           │
│ ‖ Paused                            (◎)    │   status: 11pt Rounded, x13, baseline ≈ y142
│                                       11   │   Spotify icon 21pt @ 11pt inset; clear zone ≥10.5 ✓
└────────────────────────────────────────────┘
```
- Background: `tint.surface.{light|dark}` via `containerBackground`. Marked removable for StandBy.
- Tap: opens the item in Spotify. (Use `widgetURL` for small, since only one tap target is allowed.)

### 5.3 systemSmall: "Sleeve" (art-first variant, fully compliant)

```
┌──────────────── 158 × 158 ────────────────┐
│ 13                ╭────────────╮           │   disc Ø104, centre (93,65): peeks up-right
│                 ╭─╯  ░ grooves  ╰─╮        │   plain label Ø52 (art colour), spindle
│  ┌────────────────────┐   ◐ label  │       │
│  │                    │           ╭╯       │
│  │   ARTWORK  104²    │  ╭────────╯        │   sleeve = full art 104², r4,
│  │   (still, r4)      │──╯                 │   soft shadow x2 y1 blur7 35%
│  │                    │                    │
│  │                    │             (◎)    │   icon 21 @ 11 inset
│  └────────────────────┘                    │
└────────────────────────────────────────────┘
```

### 5.4 systemMedium: "Sleeve" (default medium)

```
┌──────────────────────────────── 338 × 158 ─────────────────────────────────┐
│ 16                                                                          │
│  ┌──────────────────┐╮                  Low Sun Over                        │  title 15 Semibold, 2 lines
│  │                  │ ╲   disc Ø126     Harbour                             │  artist 13 Regular
│  │    ARTWORK       │  ╲  centre x127   Marlow Reyes                        │
│  │    126 × 126     │◐  │ peeks 48 pt                                       │  text column x204–322 (118 pt)
│  │    r4 (sleeve)   │  ╱                                                    │
│  │                  │ ╱                 ▮▮▮ Playing                         │  status 11 Rounded
│  └──────────────────┘╯                  (◎) Spotify   ← full logo ≥70 pt    │  attribution bottom-aligned
│                                                                       16    │
└─────────────────────────────────────────────────────────────────────────────┘
```
- Two tap targets: the sleeve/disc area and the text area both open Spotify ("OPEN SPOTIFY" semantics). Use `Link` for each.
- Alternative "Record" medium (setting): Inscribed disc Ø126 on the left in place of the sleeve, with the same text column.

### 5.5 systemLarge: P2 (only if cheap)

```
┌──────────────── 338 × 354 ────────────────┐
│ 16      ╭────────────────────╮             │  disc Ø220, centred, Inscribed label (art 73 pt)
│       ╭─╯                    ╰─╮           │
│      │      ┌──────────┐        │          │
│      │      │  ART 73² │        │          │
│      │      └──────────┘        │          │
│       ╰─╮                    ╭─╯           │
│ 236     ╰────────────────────╯             │
│ Low Sun Over Harbour                       │  17 Semibold, 1 line
│ Marlow Reyes                               │  15 Regular
│ ━━━━━━━━━━━━━━━━━━━──────────────          │  ProgressView(timerInterval:) 4pt, info-only
│ 0:43                              -2:40    │  11 Rounded mono
│ ▮▮▮ Playing                (◎) Spotify     │  status + full logo
└────────────────────────────────────────────┘
```

### 5.6 Lock Screen accessories

```
accessoryCircular 72²                 accessoryRectangular 160×72
   ╭──── progress ring ────╮          ┌──────────────────────────────────┐
  │  ╭── mono disc Ø56 ──╮  │         │ ╭─Ø56─╮  Low Sun Over Ha…         │  13 Semibold
  │  │   art 19 (mono)   │  │         │ │ ◐   │  Marlow Reyes             │  13 Regular 62%
  │  ╰───────────────────╯  │         │ ╰─────╯  ━━━━━━━━──────          │  3pt progress
   ╰── 3pt, timerInterval ─╯          └──────────────────────────────────┘
accessoryInline:  ♫  Low Sun Over Harbour · Marlow Reyes     (SF Symbol "opticaldisc" or "music.note"; INFERRED symbol name)
```
- Vibrant rendering. Use the **mono disc asset** (§3.4). Art via `widgetAccentedRenderingMode(.desaturated)` or `luminanceToAlpha` (system greyscale). Use opaque greys, not white opacity, for the vibrant effect (HIG, VERIFIED).
- Attribution: on the Lock Screen there's no room for a 21 pt icon on circular. Tapping opens our app, which shows attribution. **Grey area.** Prefer the rectangular accessory, which has room if we drop the progress bar. Flag for review.

### 5.7 StandBy

- The system shows two small widgets side-by-side, scaled up (HIG, VERIFIED). Recommend the **Record** small next to **Sleeve** small. Background removable means a pure black field with the disc floating, which looks good on OLED.
- Night mode (red monochrome, HIG VERIFIED): the mono disc and desaturated art take the system red. No special handling.

### 5.8 Rendering modes (iOS 26 Home Screen: light / dark / clear / tinted)

| Mode | Background | Disc | Art | Text |
|---|---|---|---|---|
| Light / Dark (`fullColor`) | `tint.surface.*` | colour disc + shadow/hairline | full colour | `ink.*` |
| **Clear** (`accented` + Liquid Glass) | removed → system glass | **mono glass disc** asset, `.widgetAccentable(false)` (primary group) | **`.widgetAccentedRenderingMode(.fullColor)`** by default. HIG explicitly suggests full-colour images for album art, smaller than the widget (VERIFIED) | system white |
| **Tinted** (`accented`) | removed → system tint | mono asset | `.fullColor` default. Setting "Tint artwork" → `.accentedDesaturated` | primary group |

`WidgetAccentedRenderingMode` cases (VERIFIED: https://developer.apple.com/documentation/widgetkit/widgetaccentedrenderingmode): `accented`, `accentedDesaturated`, `desaturated`, `fullColor` (iOS 18+).
Detect with `@Environment(\.widgetRenderingMode)` and swap the disc asset (colour ↔ mono). The Spotify icon goes into the accent group so it tints consistently.

### 5.9 Widget states

| State | Disc | Label / sleeve | Text (medium) | Small status |
|---|---|---|---|---|
| **Playing** | still (settle on change) | art | title / artist / "▮▮▮ Playing" | none |
| **Paused** | still | art | "‖ Paused" | "‖ Paused" |
| **Nothing playing** (204 / no item) | still | blank plain label (neutral, printed marks); sleeve = generic paper sleeve with die-cut circle | "Nothing playing" / "Play something in Spotify" | "• Idle" |
| **Not connected** / token revoked | disc at 38 % opacity | neutral | "Connect Spotify" / "Tap to sign in" | "• Signed out". Tap opens app onboarding |
| **Stale** (last fetch > 3 min while "playing") | still | last art | artist line → "Last seen 4 min ago" | "• Offline" (orange dot) |
| **Ad** (`currently_playing_type = ad`) | still | neutral label | "Advertisement" / "Spotify" | none |
| **Podcast / audiobook** | still | episode/show art (square) | episode / show | as playing |
| **Local file / no art** | still | neutral label with ♪ glyph | track / "Local file" | as playing |

---

## 6. Companion app

### 6.1 Onboarding (3 screens, skippable after connect)

```
┌───────────── 393 ─────────────┐   ┌───────────────────────────────┐   ┌───────────────────────────────┐
│                               │   │                               │   │   ┌─small─┐ ┌─small─┐         │
│        ╭───────────╮          │   │   Connect your account        │   │   │ disc  │ │ sleeve│         │
│      ╭─╯  spinning ╰─╮        │   │                               │   │   └───────┘ └───────┘         │
│      │   blank disc   │       │   │   We read what's playing so   │   │   ┌──── medium ────────┐      │
│      ╰─╮  (no art)  ╭─╯       │   │   your widget can show it.    │   │   └────────────────────┘      │
│        ╰───────────╯          │   │   We never change playback    │   │                               │
│                               │   │   unless you tap play/pause.  │   │  Add a widget                 │
│  Your music, on a record.     │   │                               │   │  1 Long-press Home Screen     │
│  A quiet now-playing widget   │   │  ┌─────────────────────────┐  │   │  2 Tap Edit → Add Widget      │
│  for Spotify.                 │   │  │  Continue with Spotify  │  │   │  3 Search "<app name>"        │
│                               │   │  └─────────────────────────┘  │   │                               │
│  ┌─────────────────────────┐  │   │   black/white button, mono   │   │  ┌─────────────────────────┐  │
│  │        Get started      │  │   │   Spotify icon left           │   │  │          Done           │  │
│  └─────────────────────────┘  │   │   "Not affiliated with        │   │  └─────────────────────────┘  │
│                               │   │    Spotify." footnote         │   │                               │
└───────────────────────────────┘   └───────────────────────────────┘   └───────────────────────────────┘
```
- The connect button is a monochrome capsule (black in light, white in dark) with the mono Spotify icon. Do not make it green unless it sits on pure black/white (Spotify rule).
- The "for Spotify" wording is allowed. Never imply endorsement.

### 6.2 Now Playing (hero): implemented in the prototype

```
┌───────────────── 393 × 852 ─────────────────┐
│ 9:41                              ▮▮▮ ▭     │
│  (⌄)          PLAYING ON              (···) │  y62: 36pt circle buttons, eyebrow + full logo (attribution)
│               (◎) Spotify                   │
│        ╭──────────────────────────╮         │  y112–464: disc Ø320, centred (x36.5)
│      ╭─╯                          ╰─╮       │
│     │        ╭──────────────╮        │      │  label Ø160, art 106² r4 (Inscribed)
│     │        │  ┌────────┐  │        │      │
│     │        │  │  ART   │  │        │      │
│     │        │  └────────┘  │        │      │
│     │        ╰──────────────╯        │      │
│      ╰─╮      static sheen ⟋     ╭─╯       │
│        ╰──────────────────────────╯         │
│  Low Sun Over Harbour                        │  y484: 22 Bold; artist 17 Regular (28 inset)
│  Marlow Reyes                                │
│  ━━━━━━━━━━━━━━━━━──────────────────────     │  y560: 4pt bar, info only, NO knob
│  0:43                                -2:40   │  12 Rounded mono
│                    ( ‖ )                     │  y614: 72pt play/pause, fill.control. The ONLY control
│             ( ◎ OPEN SPOTIFY )               │  y716: hairline capsule, 40pt
│                  ───────                     │
└──────────────────────────────────────────────┘
```
- Background: `tint.surface` (600 ms cross-fade). No blur, no gradient.
- Podcasts: add ⟲15 / 15⟳ buttons either side of play/pause (Spotify rule). Hidden for music.
- Play/pause through the Web API requires Spotify Premium (INFERRED). For free users, show the button disabled (Spotify requires a disabled state or no button) and add a footnote.
- Long-press the title to show a sheet with the full metadata (title, artists, album) and an "OPEN SPOTIFY" link.
- `(···)` menu: Label style, Speed, Widgets, Settings, Diagnostics.

### 6.3 Widgets (gallery and customisation, minimal)

```
┌──────────────────────────────────────────────┐
│  Widgets                                     │
│  ┌────────────┐ ┌────────────┐               │  live previews with current track
│  │  Record    │ │  Sleeve    │   small       │
│  └────────────┘ └────────────┘               │
│  ┌──────────────────────────────┐            │
│  │  Sleeve · medium             │            │
│  └──────────────────────────────┘            │
│  Label style     [Inscribed|Still|Classic⚠]  │  Classic shows: "Crops artwork; outside
│  Disc finish     [Black|Smoke]               │   Spotify's artwork guidelines."
│  Tint artwork in Tinted mode     ( off )     │
│  How to add a widget  ›                      │
└──────────────────────────────────────────────┘
```

### 6.4 Settings

Account (connected as …, Disconnect) · Playback (Speed 33⅓/45, Spin in app on/off, honours Reduce Motion automatically) · Appearance (System/Light/Dark for app chrome only) · Widgets › · Diagnostics › · About (version, "Not affiliated with Spotify", open-source licences, Spotify attribution).

### 6.5 Diagnostics / troubleshooting

```
┌──────────────────────────────────────────────┐
│  Diagnostics                                 │
│  Connection        ● Connected (token 41m)   │  green/orange/red dot + text (never colour alone)
│  Last poll         12:04:31 · 200 OK · 180ms │
│  Now playing       Low Sun Over Harbour      │
│  Widget reloads    7 today · last 12:03:10   │
│  Rate limit        none                      │
│  Cached art        12 items · 1.8 MB         │
│  [ Reload widgets ]  [ Clear cache ]         │
│  [ Copy debug log ]                          │
│  Troubleshooting ›  (widget stuck? → steps)  │
└──────────────────────────────────────────────┘
```
Font: SF Mono 13 for values. Rounded-rect rows grouped like Settings.

### 6.6 Edge cases (app)

| Case | Treatment |
|---|---|
| Missing artwork | neutral label + ♪ glyph, neutral surface; never generate fake art |
| Podcast / audiobook | show/episode art, ±15 s controls, "EPISODE" eyebrow |
| Ad | neutral label, disc keeps spinning (audio is playing), text "Advertisement", controls disabled |
| Local file | ♪ label, "Local file" artist fallback if missing |
| Offline | last known track, disc spins down and stops, banner "Offline · showing last known" (secondary ink, no red) |
| Signed out / token revoked | disc 38 %, full-width "Connect Spotify" primary button replaces play/pause |
| Very long titles | 1 line + tail truncation, full text via long-press sheet |
| Greyscale art | neutral surface (C < 0.02), Inscribed surround = edge grey |
| Private session / nothing playing | Idle state |

---

## 7. Accessibility

- VoiceOver: the disc is decorative (`accessibilityHidden`). The art is "Album artwork". The widget gets one combined label: "Now playing on Spotify: Low Sun Over Harbour by Marlow Reyes. Playing." The progress bar is announced as "0:43 of 3:24" with no adjustable trait (info only).
- Reduce Motion: no spin and no settle (§4.5). Increase Contrast: `ink.secondary` → 75 %, rim hairline 14 %, label ring line 30 %.
- Never use colour alone for state. Every status pairs a glyph with a word.
- Minimum hit target 44 pt in app. Text ≥ 11 pt in widgets.

---

## 8. Prototype (`design/vinyl-prototype.html`): what it shows

- True-size **small Record, small Sleeve, medium Sleeve** widgets on a Home Screen, **Lock Screen circular + rectangular** accessories, and a **393 pt Now Playing** screen with a 320 pt disc.
- Controls: Play/Pause (spin-up/down inertia, live rpm readout), **Next track** (450 ms label cross-fade, rotation preserved, surface tint cross-fade), Look **Light/Dark/Clear/Tinted**, Label **Inscribed/Still/Full-bleed/Plain**, State **Track/No art/Idle/Signed out**, speed 33⅓/45, art-in-colour toggle, Reduce Motion, **Spec overlay** (pink measurement guides).
- All art, titles and artists are generated or fictional. The attribution mark is a neutral placeholder; use the official logo files in the app.
- The widgets spin in the prototype only to show the feel. On device they are still unless the experimental flag is on (§5.1).

---

## 9. Open items and hand-offs

1. **Agent 1/2:** confirm the deep-link URL to open the current item in Spotify, and the Premium requirement for play/pause. Choose the widget refresh policy behind the "Stale" state threshold (3 min proposed).
2. **Agent 2:** decide on the experimental continuous spin (private API). The design does not depend on it.
3. **App name** must not start with "Spot" or sound like Spotify. "for Spotify" as a subtitle is OK. The icon must not echo the Spotify mark (suggest: a black disc with an off-centre warm label, no arcs).
4. Re-check on the Spotify page: the #191414 fallback value, and whether "px" minimums mean CSS px or device pixels. I treated them as **pt** (conservative).
5. Attribution on the circular Lock Screen accessory is a grey area (§5.6).

---

## 10. Sources

- Spotify Design & Branding Guidelines: https://developer.spotify.com/documentation/design (VERIFIED, quotes above)
- Spotify Developer Policy: https://developer.spotify.com/policy (VERIFIED: II.4.1, II.4.2, II.4.3, II.5, VI.1, VI.2)
- Apple HIG, Widgets: https://developer.apple.com/design/human-interface-guidelines/widgets (VERIFIED: size table, 16/11 pt margins, appearances incl. clear/tinted, full-colour album art guidance, StandBy, 2 s animation, 11 pt text minimum, Dynamic Type range)
- WidgetAccentedRenderingMode: https://developer.apple.com/documentation/widgetkit/widgetaccentedrenderingmode (VERIFIED: cases and iOS 18 availability)
- MD Vinyl App Store listing: https://apps.apple.com/us/app/id1606306441 (VERIFIED via fetch summary)
- MD Vinyl on Product Hunt: https://www.producthunt.com/posts/md-vinyl (INFERRED, search summary)
- VinylPod App Store listing: https://apps.apple.com/app/id6443989711 (VERIFIED via fetch summary)
- TikWidget (search summary): https://apps.apple.com/app/id1556054655 (INFERRED)
- Widget animation workaround discussion: https://hackaday.com/2025/05/17/animated-widgets-on-apple-devices-via-a-neat-backdoor, https://github.com/octree/ClockHandRotationKit (INFERRED, not fetched)
