# Installing Spindle on your iPhone from Windows

We install with **iloader** and a free Apple ID.

## Which tools work (tested 2026-11-12, iOS 27.2)

| Tool | Result |
|---|---|
| **iloader** "Import IPA" | ✅ **Works.** Signs in; registers an App Group (`group.dev.spindlevinyl.app.<TEAMID>`); shared folder OK |
| Sideloadly | ❌ Installs and spins, but grants **no App Group** on a free Apple ID, so the widget can't share data with the app |
| SideStore | ❌ In-app sign-in fails with **-80045**, a known open SideStore bug since ~Oct 2026 ([issue #1709](https://github.com/SideStore/SideStore/issues/1709)). Worth retrying after a SideStore update: it would refresh on the phone with no PC. |

## What you need

- Windows PC (64-bit), iPhone, USB cable
- **iTunes** from Apple's site: <https://www.apple.com/itunes/download/win64>
- **iloader**: <https://iloader.app> (the MSI is recommended)
- An **Apple ID**. You type it into iloader yourself; it never goes into the code or to me.
- **Developer Mode** on the iPhone: Settings › Privacy & Security › Developer Mode, then restart.

## 1. Get `Spindle.ipa`

1. Push to `main`. GitHub's **Actions** tab builds the app; the **ios** run takes about 10–15 minutes.
2. Open the green run and download the **Spindle** artifact.
3. Unzip it to get `Spindle.ipa`.

## 2. Install with iloader

1. Connect the iPhone by USB, unlock it, and trust the computer if asked.
2. Open **iloader**, sign in with your Apple ID, and select your iPhone.
3. Choose **Import IPA** and pick `Spindle.ipa`.
4. If iOS asks, go to **Settings › General › VPN & Device Management**, tap your Apple ID and **Trust**.

## 3. Check it worked

1. Add the **Spin test** widget (small and medium) to your Home Screen. Deleting the app also removes its widgets.
2. Open **Spindle** and pull down to refresh.

| Section | Field | Expected |
|---|---|---|
| App Group | Shared folder | OK ✅ |
| App Group | Resolved ID | `group.dev.spindlevinyl.app.<TEAMID>` |
| Widget | Last widget refresh | A recent time; this proves the widget can use the shared folder too |

The medium widget's top-left corner should say **Shared folder ✓**.

---

## Weekly re-install (free Apple ID)

Free signatures last **7 days**; Diagnostics shows the date, with a ⚠️ in the last 2 days. Before it expires, repeat **step 2** with the same `Spindle.ipa` or a newer one. iloader doesn't refresh in the background, so this needs the PC and USB, about a minute.

If the signature expires anyway, the app won't open until you re-install. Your data in the shared folder should survive (not yet tested).

## Updating to a new build

Download the newer `Spindle.ipa` and install it the same way. It replaces the old version and keeps the same app ID. **Don't change bundle IDs**: a free Apple ID allows 10 app IDs per 7 days, and Spindle uses 2.

## App slots

A free Apple ID allows **3 sideloaded apps** at once. Spindle uses one. If SideStore is still installed from the earlier attempt, it uses another. Delete it if you need the slot.

## Troubleshooting

| Problem | Fix |
|---|---|
| iloader doesn't see the iPhone | Unlock the phone, re-plug, re-trust; reinstall iTunes from apple.com |
| "Maximum apps" / App ID limit | Remove an older sideloaded app; don't change bundle IDs; wait for old App IDs to expire (7 days) |
| Shared folder **Unavailable ❌** | Send me the Diagnostics screenshot, especially the "Groups in profile" row |
| "Spin test" missing from the widget gallery | Open Spindle once, then try again; restart if needed |
| App won't open | Signature expired; re-install with iloader |
| iloader errors | iloader support is the idevice Discord (linked from SideStore's docs) |

## Optional: run the Core tests on Windows

```bash
winget install --id Swift.Toolchain -e --source winget
```
```bash
swift test --package-path Packages/Core
```

Requires Visual Studio 2022 Build Tools with the Windows 11 SDK; see swift.org/install/windows. CI runs these tests anyway.
