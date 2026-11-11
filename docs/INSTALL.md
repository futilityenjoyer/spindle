# Installing Spindle on your iPhone from Windows

We install with **SideStore** and a free Apple ID.

> **Why not Sideloadly?** Tested on 2026-11-12: Sideloadly installs and the vinyl spins, but on a free Apple ID it does **not** enable *App Groups*. Without App Groups the widget can't share data with the app, and later can't read your Spotify sign-in. SideStore documents App Group support.

Steps marked **(docs)** follow SideStore's official guide at [docs.sidestore.io](https://docs.sidestore.io/docs/installation/prerequisites); check there if a screen looks different. Steps marked **(not in docs)** are standard SideStore UI that its docs don't describe.

## What you need

- Windows PC: 64-bit, and not Windows 10 on Arm. Needed only for the first SideStore install.
- iPhone with a passcode, a USB cable, and **Wi-Fi**. SideStore doesn't work over mobile data.
- An **Apple ID**. You type it into iloader and SideStore yourself; it never goes into the code or to me.
- The code on GitHub. Each push to `main` builds `Spindle.ipa` in the **Actions** tab.

---

## 1. Remove the Sideloadly copy (once)

Delete **Spindle** from your iPhone: long-press the icon, then **Remove App**, then **Delete App**. This lets SideStore register the app fresh with App Groups turned on. It also frees the app slot: a free Apple ID allows 3 apps, and SideStore takes one of them.

## 2. Prepare Windows (once) (docs)

1. Install **iTunes**. Apple's version is recommended: <https://www.apple.com/itunes/download/win64>.
2. Install **iloader** (MSI recommended): <https://iloader.app>.

## 3. Prepare the iPhone (once) (docs)

1. From the App Store, install **LocalDevVPN**: <https://apps.apple.com/app/localdevvpn/id6755608044>.
2. Open it and **Connect**, allowing the VPN configuration when asked.
   - It connects only to your own phone; SideStore uses it to sign apps on the device.
   - **It must be on whenever SideStore installs, updates or refreshes apps.**

## 4. Install SideStore (once) (docs)

1. Connect the iPhone by USB. Unlock it and trust the computer if asked.
2. Open **iloader** and sign in with your Apple ID. It's case-sensitive.
3. Select your iPhone, then **Install SideStore (Stable)**.
4. On the iPhone, go to **Settings › General › VPN & Device Management**. Under *Developer App*, tap your Apple ID, then **Trust**.
5. **Developer Mode** should already be on from the Sideloadly test. If not: **Settings › Privacy & Security › Developer Mode** → on → restart.
6. Make sure **LocalDevVPN** is connected, then open **SideStore** and sign in with the same Apple ID.
7. In **My Apps**, tap the **7 DAYS** counter next to SideStore to refresh it. If asked to revoke or create a certificate, tap **Yes** or **Refresh Now**.

If iloader itself has problems, SideStore's docs send iloader questions to the idevice Discord rather than SideStore's.

## 5. Get `Spindle.ipa` onto the iPhone

Pick either option:
- **On the iPhone:** in Safari, open your repo → **Actions** → the latest green **ios** run. Download the **Spindle** artifact (you must be signed in to GitHub). In the Files app, tap the `.zip` to unzip it.
- **From the PC:** download and unzip the artifact, then put `Spindle.ipa` in iCloud Drive or OneDrive so it appears in the Files app.

## 6. Install Spindle with SideStore (not in docs)

1. Make sure **LocalDevVPN** is connected.
2. Open **SideStore** → **My Apps** → tap **+** (top-left) → choose `Spindle.ipa`.
3. Wait for it to finish. Spindle appears on your Home Screen.

## 7. Check it worked

1. Open **Spindle**. In **App Group** you should now see:

   | Field | Expected |
   |---|---|
   | Groups in profile | `group.dev.spindlevinyl.shared.<TEAMID>` |
   | Resolved ID | The same value |
   | Shared folder | OK ✅ |

2. Add the **Spin test** widget (small and medium) to your Home Screen if it's not there.
3. Re-open Spindle and pull down to refresh. **Widget** should now show **Last widget refresh** with a recent time.
4. The medium widget's top-left corner should say **Shared folder ✓**.

Send me a screenshot of the App Group and Widget sections.

---

## Weekly refresh (free Apple ID)

Signatures last **7 days**; Diagnostics shows the expiry date.
- SideStore refreshes apps **in the background** on the phone while on Wi-Fi.
- You can also open SideStore → **My Apps** → tap the days counter.
- Keep **LocalDevVPN** connected when refreshing.

**Pairing file:** SideStore's docs warn it can expire after an iOS update or reset, or at random. If refreshing starts failing, follow their [pairing file guide](https://docs.sidestore.io/docs/advanced/pairing-file).

## Updating Spindle to a new build

Download the new `Spindle.ipa` and install it the same way: **My Apps → +**, with the VPN connected. It replaces the old version and keeps the same app ID. Don't change bundle IDs: a free Apple ID allows 10 app IDs per 7 days, and Spindle uses 2.

## Troubleshooting

| Problem | Fix |
|---|---|
| iloader doesn't see the iPhone | Unlock the phone, re-plug, re-trust; reinstall iTunes from apple.com |
| SideStore install/refresh fails | Check LocalDevVPN is connected and you're on Wi-Fi; see [SideStore common issues](https://docs.sidestore.io/docs/troubleshooting/common-issues) |
| "Maximum apps" error | Free accounts allow 3 apps including SideStore; remove an older sideloaded app |
| Shared folder still **Unavailable ❌** | Send me the Diagnostics screenshot (Groups in profile row) |
| "Spin test" missing from the widget gallery | Open Spindle once, then try again; restart if needed |
| App won't open | Signature expired; refresh in SideStore (VPN on) |

## Optional: run the Core tests on Windows

```bash
winget install --id Swift.Toolchain -e --source winget
```
```bash
swift test --package-path Packages/Core
```

Requires Visual Studio 2022 Build Tools with the Windows 11 SDK; see swift.org/install/windows. CI runs these tests anyway.
