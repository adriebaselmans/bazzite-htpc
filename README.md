# bazzite-htpc

A custom [Bazzite](https://bazzite.gg) image for a living-room box: Steam Game
Mode as the shell, [Kodi](https://kodi.tv) with the
[xstreamflex](https://github.com/adriebaselmans/xstreamflex) add-on for IPTV, and
[SmartTube](https://github.com/yuliskov/SmartTube) running in Waydroid's Android
TV image.

Built to replace an ageing NVIDIA Shield on a mini-PC (AMD + Radeon 780M).

## What is where, and why

The setup is split across two layers, and the split is not cosmetic:

| Layer | Contains | Why here |
| --- | --- | --- |
| **Image** (`recipes/recipe.yml`) | Kodi + Flatseal flatpaks, the `ujust` recipes | Declarative, reproducible, survives a reinstall, updates itself |
| **`ujust setup-htpc`** (`files/justfiles/htpc.just`) | Waydroid init, SmartTube, xstreamflex, Steam entry | Waydroid downloads its Android images at init time; Steam/Kodi config lives in `$HOME`. Neither can be baked into a system image. |

`base-image` is **`bazzite-deck`** — the Handheld/HTPC variant, which boots
straight into Gamescope Game Mode. Deliberately not a `-nvidia` variant:
Waydroid does not work on Nvidia at all, which would take SmartTube with it.

## Installing on a machine

### 1. Write the USB (from any OS)

Download the ISO from [bazzite.gg](https://bazzite.gg) — its hardware selector
serves the right build; take the **handheld/HTPC** one (`-deck`), not the plain
desktop edition and not an `-nvidia` variant.

Write it with Rufus, Ventoy or `dd`. With Rufus, **pick "DD Image" mode** when
prompted: in ISO mode the stick does not show up as a boot option at all, which
looks like a BIOS problem rather than a flashing problem.

### 2. Install

Boot the USB and run the installer. **Attach a physical USB keyboard** — the
Secure Boot and disk-encryption prompts do not accept an on-screen one.

### 3. Enrol the Secure Boot key

On the reboot after install a blue MokManager screen appears. Choose **Enroll
MOK** and enter:

```
universalblue
```

Nothing is echoed as you type (deliberate), and the prompt is always **QWERTY**
regardless of your own layout. Skip this with Secure Boot enabled in the BIOS
and Bazzite will not boot at all.

If Secure Boot was off during install, do it afterwards with
`ujust enroll-secure-boot-key` (same password), then enable Secure Boot in the
BIOS.

### 4. Rebase onto this image

First boot lands in Game Mode. Switch to Desktop Mode (Steam menu → Switch to
Desktop), open a terminal:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/adriebaselmans/bazzite-htpc:latest
systemctl reboot
```

From then on the machine updates along with this image, and the previous version
stays in the boot menu to roll back to.

### 5. Set up the HTPC layer

**Start Kodi once first** — otherwise `~/.var/app/tv.kodi.Kodi` does not exist
yet and the xstreamflex step stops with an error. Then:

```bash
ujust setup-htpc
```

Sanity check that the image carries what it should: `ujust --list` should show
`setup-htpc`.

## Forking this repo

The signing key here belongs to this repo. If you fork it, generate your own or
the build fails with *"Public key './cosign.pub' does not match private key"*:

```bash
cosign generate-key-pair          # leave the passphrase empty
gh secret set SIGNING_SECRET < cosign.key
```

Commit the generated `cosign.pub`; never commit `cosign.key` (it is gitignored).
Use `gh secret set` rather than pasting into the web UI — a truncated or
whitespace-mangled paste produces *"Unable to find private/public key pair"*,
which reads like a missing secret rather than a corrupted one.

Actions are disabled by default on a fresh fork; enable them under the Actions
tab.

## Commands

| Command | Does |
| --- | --- |
| `ujust setup-htpc` | Everything below except `htpc-remote` |
| `ujust htpc-waydroid` | Init Waydroid with the Android TV image (`ujust htpc-waydroid 1` forces a clean re-init) |
| `ujust htpc-smarttube` | Install the latest **stable** SmartTube (arm64) |
| `ujust htpc-xstreamflex` | Build and install the xstreamflex add-on into the Kodi flatpak |
| `ujust htpc-steam-shortcut` | Add Kodi to Steam so Game Mode can see it |
| `ujust htpc-remote` | Pair a Bluetooth remote/controller |

All of them are safe to re-run.

## Known caveats

- **Waydroid under Game Mode is the biggest unknown.** Game Mode runs under
  `gamescope`, a nested Wayland compositor, while Waydroid wants a Wayland
  session of its own. Standalone Waydroid on Bazzite is documented and
  supported; launching SmartTube *from within* Game Mode is not verified. Test
  this early. Fallback: run Waydroid from desktop mode and keep Game Mode for
  games.
- **SmartTube ships no x86_64 APK** (only arm64-v8a, armeabi-v7a, universal and
  32-bit x86). The Android TV image bundles ARM translation, which is what makes
  the arm64 build work here.
- **The back button** does not work when SmartTube is started via
  `waydroid app launch`. Start it from the Android TV launcher instead.
- **Widevine L3** caps DRM-protected content at 1080p. YouTube's ordinary
  streams are not Widevine-protected so 4K should be fine — but verify it rather
  than assume.
- **Shield remote pairing can be lost across reboots.** Known issue; the
  circulating fix explicitly does not solve it. A Flirc USB (IR) or a
  Pulse-Eight USB-CEC adapter is more reliable — this machine has no HDMI-CEC of
  its own, unlike the Shield.
- **Kodi must have been started once** before `ujust htpc-xstreamflex` works; it
  needs `~/.var/app/tv.kodi.Kodi` to exist.

## xstreamflex under Flatpak

Works unmodified. Every path derives from `xbmcvfs.translatePath()` on the
add-on profile, so under Flatpak it resolves to
`~/.var/app/tv.kodi.Kodi/data/...` — the `.strm`/`.nfo` library, the M3U export
and the IPTV Simple configuration all land inside the same sandbox Kodi reads
from. Nothing needs to reach outside it.

The exception is putting the library on a NAS or external disk; that needs
filesystem permissions granted via Flatseal, which is why it is in the image.
