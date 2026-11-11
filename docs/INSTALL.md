# Installing Spindle on your iPhone from Windows (M0 spin test)

This first build has **no Spotify yet**. It answers one question: *does the vinyl actually spin on your iPhone?* It also checks that the app and widget can share data after sideloading.

Total time the first time: about 45 minutes, most of it one-time setup.

## What you need

- Windows 11 PC, iPhone, USB cable
- A free **GitHub** account
- An **Apple ID**. Use a secondary one for sideloading if you have it. You type it into the sideloading tool yourself; it never goes into the code or to me.

---

## 1. Put the code on GitHub (once)

1. On github.com, create a **new public repository** named `spindle`. Don't add a README, .gitignore or licence.
2. In this project folder, run the commands below (or ask me to do the git part), replacing `YOUR-USERNAME`:

```bash
git init -b main
```
```bash
git add .
```
```bash
git commit -m "M0: pipeline and spin test"
```
```bash
git remote add origin https://github.com/YOUR-USERNAME/spindle.git
```
```bash
git push -u origin main
```

## 2. Let the cloud Mac build it

1. On your repo page, open the **Actions** tab. The **ios** workflow starts on every push.
2. It runs three jobs: *Core package tests*, then *IPA (xcode-26.6)* and *IPA (xcode-27)*. Expect about 10–20 minutes.
3. When a job is green, open the run and scroll to **Artifacts**. Download `Spindle-xcode-26.6` (and later `Spindle-xcode-27`).
4. Each download is a `.zip`. Unzip it to get `Spindle-xcode-26.6.ipa`.

If the **xcode-27** job fails, that's fine for now: it runs on GitHub's *preview* image. Tell me the error and test the 26.6 build first.

## 3. Prepare Windows (once)

1. If you have **iTunes** or **iCloud** from the Microsoft Store, uninstall them.
2. Install **iTunes** and **iCloud** from **apple.com**, the web/desktop installers. Sideloadly requires these versions.
3. Install **Sideloadly** from [sideloadly.io](https://sideloadly.io).

## 4. Prepare the iPhone (once)

1. Connect it by USB, unlock it, and tap **Trust This Computer**.
2. After the first install (step 5), go to **Settings › Privacy & Security › Developer Mode**, turn it **on**, and restart when asked.
3. If iOS says the developer isn't trusted, go to **Settings › General › VPN & Device Management**, tap your Apple ID and **Trust** it.

## 5. Install the test build

1. Open Sideloadly. Your iPhone should appear in the device list.
2. Drag `Spindle-xcode-26.6.ipa` onto Sideloadly.
3. Enter your Apple ID in Sideloadly and press **Start**.
4. Wait for "Done". The **Spindle** app appears on your Home Screen.

## 6. Run the spin test

1. **Open Spindle once.** You'll see the Diagnostics screen.
2. Go to the Home Screen, long-press an empty area, then **Edit › Add Widget**. Search **Spindle** and add **Spin test**. Add both the **small** and the **medium** size.
3. **Watch for 10 seconds.** Does the record turn? The white mark on the label makes it obvious.
   - The small widget turns at 16⅔ RPM.
   - The medium widget shows 16⅔ and 33⅓ side by side, so you can pick the speed you like.
4. **Open Spindle again** and check the sections below. Pull down to refresh.

| Section | Field | What you should see |
|---|---|---|
| Widget | Last widget refresh | A time from a few moments ago |
| Widget | Spin effect type | Present |
| App Group | Shared folder | OK ✅ |
| App Group | Resolved ID | Probably `group.dev.spindlevinyl.shared` followed by something extra; that's normal |
| Install | Signature expires | About 7 days from now |

## 7. Tell me the results

Send me:
- **Spins / doesn't spin** for each build, and which speed looks better.
- A **screenshot of the Diagnostics screen**.
- Your **iOS version** (Settings › General › About).

Then repeat steps 5–6 with `Spindle-xcode-27.ipa`. It has the same app ID, so it replaces the first one.

---

## Weekly re-signing (free Apple ID)

Free signatures last **7 days**. Diagnostics shows the expiry date. Before it runs out, choose one:
- **Re-install from Sideloadly.** Same file, same Apple ID; takes a minute.
- **Sideloadly's auto-refresh.** It needs the PC on, on the same Wi-Fi, with Wi-Fi sync enabled in iTunes.
- **SideStore,** which refreshes on the phone itself. We'll set this up once the real widget exists.

## Troubleshooting

| Problem | Fix |
|---|---|
| Sideloadly doesn't see the iPhone | Unlock the phone, re-plug, re-trust; make sure iTunes is the apple.com version |
| "Maximum App IDs" / limit errors | A free Apple ID allows 10 app IDs per 7 days; Spindle uses 2. Don't rename the app or change bundle IDs. Wait for the oldest to expire. |
| "Spin test" not in the widget gallery | Open the Spindle app once, then try again. Restart the phone if needed. |
| Shared folder shows **Unavailable ❌** | The App Group was lost during signing. Send me the Diagnostics screenshot and the Sideloadly log. |
| Record shows but doesn't turn | That's a valid test result. Note which build, and send the Diagnostics screenshot. |
| App won't open after a week | The signature expired. Re-install from Sideloadly. |

## Optional: run the Core tests on Windows

The `Packages/Core` code (profile parsing, App Group resolution) is plain Swift and runs on Windows:

```bash
winget install --id Swift.Toolchain -e --source winget
```
```bash
swift test --package-path Packages/Core
```

The Swift toolchain needs Visual Studio 2022 Build Tools with the Windows 11 SDK; see swift.org/install/windows. CI runs these tests anyway, so this is only for faster feedback.
