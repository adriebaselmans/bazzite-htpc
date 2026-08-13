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

### 4. Rebase onto this image — two steps

First boot lands in Game Mode. You do **not** need Desktop Mode for this: press
`Ctrl`+`Alt`+`F4` for a TTY and log in. That also sidesteps two current Bazzite
bugs — a Steam update loop that can trap you in Game Mode, and "Switch to
Desktop Mode" going missing from the Steam menu. (`Ctrl`+`Alt`+`F1` gets you
back to the graphical session.)

Skip any offered system update first; the rebase replaces the whole image
anyway.

The rebase has to happen twice, because a stock Bazzite install trusts only
Universal Blue's keys and cannot verify an image signed with this repo's key
until that key is present. The first rebase is what installs it:

```bash
rpm-ostree rebase ostree-unverified-registry:ghcr.io/adriebaselmans/bazzite-htpc:latest
systemctl reboot
```

Unverified is safe here — it is your own image, and this step is what writes
your public key into `/etc/containers/policy.json`. After the reboot, switch to
the signed reference so every later update is verified:

```bash
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/adriebaselmans/bazzite-htpc:latest
systemctl reboot
```

Stopping after the first command works, but leaves the machine updating without
signature verification — which is the whole point of the cosign setup.

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

## Wii U emulation (Cemu, via EmuDeck)

```bash
ujust setup-emulation     # installs EmuDeck through Bazzite's own portal
ujust emulation-paths     # where ROMs, config, keys and saves live
ujust emulation-tune      # performance checklist for the 780M
ujust emulation-steam     # getting games into Steam with artwork
```

EmuDeck is installed via **`bazzite-portal`**, which ships with Bazzite itself —
there is no custom installer here. EmuDeck then owns the emulation stack: it
installs Cemu, creates `~/Emulation`, and bundles its own Steam ROM Manager.

Because it owns that stack, this image deliberately does **not** also ship Cemu
or Steam ROM Manager as flatpaks. Installing both leaves you with two Cemus and
two SRMs holding separate configs, which is exactly how duplicate Steam
shortcuts happen.

### Where things live

| What | Where |
| --- | --- |
| Your game dumps | `~/Emulation/roms/wiiu/roms` |
| Saves / persistent storage | `~/Emulation/roms/wiiu/mlc01` |
| Cemu config, controller profiles | `~/.config/Cemu/` |
| Graphic packs, shader cache, `keys.txt` | `~/.local/share/Cemu/` |
| EmuDeck itself | `~/Emulation/tools/` |
| Steam shortcuts | Steam's `shortcuts.vdf`, written by Steam ROM Manager |

No game content, keys or BIOS files ship here or are downloaded by any recipe —
provide your own dumps. Prefer decrypted `.wua`/`.rpx`; Cemu is moving away from
encrypted `.wud`/`.wux`.

### Known trade-off: Cemu's AppImage channel

EmuDeck installs Cemu as an **AppImage**. In May 2026 Cemu's AppImage and Ubuntu
zip release assets on GitHub were replaced with a credential stealer, uploaded by
an account with no prior contribution to the repo; the Windows build, the macOS
build, the git tag and the Flathub Flatpak were all untouched
([cemu-project/Cemu#1911](https://github.com/cemu-project/Cemu/issues/1911)).
Those assets have since been restored.

Flathub builds and signs from source, so that channel remains the safer one, but
EmuDeck does not support a Flatpak Cemu yet
([dragoonDorise/EmuDeck#1140](https://github.com/dragoonDorise/EmuDeck/issues/1140)).
This setup accepts that trade-off in exchange for EmuDeck's integration.

### Two things that bite

**Close Steam completely before running Steam ROM Manager.** It edits Steam's
shortcuts file directly; with Steam running, your new entries are discarded when
it exits.

**Never enable Proton compatibility** on Cemu or on the games SRM adds — this is
a native Linux build and Proton breaks it.

Performance settings are a printed checklist rather than a generated
`settings.xml`: a malformed one stops Cemu from starting, and overwriting an
existing one discards controller profiles already set up.

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
| `ujust htpc-steam-shortcut` | Add Kodi and Waydroid to Steam so Game Mode can see them |
| `ujust htpc-remote` | Pair a Bluetooth remote/controller |

All of them are safe to re-run.

## Known caveats

- **Use the `a13-tv` image, never `a16-tv`.** Android 16 needs the `aidl6`
  servicemanager protocol and the host's libgbinder only speaks up to `aidl4`,
  so the container boots but every waydroid command retries
  `Failed to get service waydroidplatform` forever. Switching the image also
  means wiping `~/.local/share/waydroid/data` (as root), or the new Android
  hangs on the old userdata — `IP address: UNKNOWN` is the symptom.
- **Waydroid under Game Mode is verified working** (2026-08-13), end to end:
  the Steam tile brings up the Android TV home screen and SmartTube plays from
  there. `ujust htpc-steam-shortcut` adds Bazzite's
  `/usr/bin/waydroid-launcher` as the Steam target; it runs Waydroid inside
  `cage`, which nests under `gamescope`, and its `pkexec` calls are already
  allowed for the `wheel` group so nothing prompts for a password. Give the
  first launch after a boot a minute or two — that is Android booting, not a
  hang. The launcher also accepts arguments
  (`waydroid-launcher app launch org.smarttube.stable`) if you want a one-tap
  SmartTube tile — but see the back-button caveat below.
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
