# bazzite-htpc

A custom [Bazzite](https://bazzite.gg) image for a living-room box: Steam Game
Mode as the shell, [Kodi](https://kodi.tv) with the
[xstreamflex](https://github.com/adriebaselmans/xstreamflex) add-on for IPTV,
native [FreeTube](https://github.com/FreeTubeApp/FreeTube) for YouTube, and
[SmartTube](https://github.com/yuliskov/SmartTube) running in Waydroid's Android
TV image.

Built to replace an ageing NVIDIA Shield on a mini-PC (AMD + Radeon 780M).

> **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** is the reference for how the
> whole thing fits together: the three repositories, the four storage layers,
> where every file actually lives, the Flatpak and Steam mechanics that keep
> mattering, and a diagnostics playbook. Read that when something behaves
> strangely; read on here to install it.

## What is where, and why

The setup is split across two layers, and the split is not cosmetic:

| Layer | Contains | Why here |
| --- | --- | --- |
| **Image** (`recipes/recipe.yml`) | Kodi + Flatseal flatpaks, the `ujust` recipes | Declarative, reproducible, survives a reinstall, updates itself |
| **`ujust setup-htpc`** (`files/justfiles/htpc.just`) | Waydroid init, SmartTube, native FreeTube, xstreamflex, Steam entries | Waydroid downloads its Android images at init time; Steam/Kodi config lives in `$HOME`. Neither can be baked into a system image. |

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

### Native YouTube with FreeTube

FreeTube is included as a native Linux Flatpak. It runs directly on Bazzite,
without Waydroid or Android TV, and is intended for the ad-free YouTube
workflow on this HTPC. Its data is kept in
`~/.var/app/io.freetubeapp.FreeTube/`.

The full `ujust setup-htpc` command installs FreeTube and adds it to Steam. On
an existing installation that already has Kodi and Waydroid configured, use
the smaller migration path instead:

```bash
ujust htpc-freetube

# Close Steam completely before changing its non-Steam shortcuts.
ujust htpc-steam-freetube
ujust htpc-steam-artwork
```

The result is a native **FreeTube** tile in Game Mode. The artwork helper also
repairs the existing Spotify tile with a capsule, portrait poster and icon.
Restart Steam after the artwork command; Steam caches `shortcuts.vdf` while it
is running. If SteamTinkerLaunch is unavailable, add FreeTube manually as a
non-Steam game:

```text
Executable:    /usr/bin/flatpak
Launch options: run io.freetubeapp.FreeTube
```

FreeTube is deliberately separate from SmartTube. SmartTube remains available
through Waydroid for the Android-TV interface, account integration and
remote-focused experience; FreeTube is the lightweight native Linux option.

## Nintendo Switch emulation (Eden, via EmuDeck)

```bash
ujust setup-emulation     # installs EmuDeck through Bazzite's own portal
ujust emulation-paths     # where ROMs, config, keys and saves live
ujust emulation-tune      # performance checklist for the 780M
ujust emulation-steam     # getting games into Steam with artwork
```

EmuDeck is installed via **Bazzite Portal** (package `bazzite-portal`, actual
command `yafti_gtk.py`), which ships with Bazzite itself — there is no custom
installer here. EmuDeck then owns the emulation stack: it
installs emulators, creates `~/Emulation`, and bundles its own Steam ROM Manager.

Because it owns that stack, this image deliberately does **not** also ship
emulators or Steam ROM Manager as flatpaks. Installing both leaves you with
duplicates holding separate configs, which is exactly how duplicate Steam
shortcuts happen.

In EmuDeck's Custom Install, choose **Linux PC** (not Steam Deck) for the
platform, then enable **Eden** as the Switch emulator. EmuDeck 2.5.0's Eden
installer is broken (see Known caveats below); the manual fix is to download
Eden's AppImage directly from https://git.eden-emu.dev/eden-emu/eden/releases
(pick the `-amd64-clang-pgo` build), place it in `~/Applications/`, and `chmod
+x` it. EmuDeck's launcher scripts already search that folder, so Steam ROM
Manager will pick it up automatically.

Nintendo Switch emulation needs game dumps plus `prod.keys` and `title.keys`
(decrypted from your own hardware), and system firmware (also dumped from your
own console). Keys go in `~/.local/share/eden/keys/`, and firmware must be
imported through Eden's own settings UI (look for a firmware/system-files
install option in its menus). Do **not** place keys or firmware in
`~/Emulation/bios/eden/` — that folder is a dead end; Eden does not read from
it at all.

For Steam ROM Manager, choose the integration level "High / Steam ROM Manager"
(not EmulationStation), which generates a "Nintendo Switch - Eden" parser that
scans `~/Emulation/roms/switch/` for game files (`.kip`, `.nca`, `.nro`, `.nso`,
`.nsp`, `.xci` in any case) and adds each to Steam with its own tile.

### Where things live

| What | Where |
| --- | --- |
| Your game dumps | `~/Emulation/roms/switch/` |
| Saves / persistent storage | `~/.local/share/eden/nand/` (created by Eden's firmware import) |
| Eden config, settings | `~/.config/eden/` |
| Keys and firmware | `~/.local/share/eden/keys/` and `~/.local/share/eden/nand/` |
| EmuDeck itself | `~/Emulation/tools/` |
| Steam shortcuts | Steam's `shortcuts.vdf`, written by Steam ROM Manager |

No game content, keys or firmware ship here or are downloaded by any recipe —
provide your own dumps from your own hardware.

### Two things that bite

**Close Steam completely before running Steam ROM Manager.** It edits Steam's
shortcuts file directly; with Steam running, your new entries are discarded when
it exits.

**Never enable Proton compatibility** on Eden or on the games SRM adds — this is
a native Linux build and Proton breaks it.

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
| `ujust htpc-freetube` | Check/install native FreeTube (no Waydroid) |
| `ujust htpc-kodi-locale` | Stop Kodi inheriting Steam's `LC_ALL=C` (breaks accented filenames) |
| `ujust htpc-xstreamflex` | Build and install the xstreamflex add-on into the Kodi flatpak |
| `ujust htpc-steam-shortcut` | Add Kodi, FreeTube and Waydroid to Steam so Game Mode can see them |
| `ujust htpc-steam-freetube` | Add only FreeTube to an already configured Steam setup |
| `ujust htpc-steam-artwork` | Apply custom FreeTube and Spotify Steam artwork |
| `ujust htpc-remote` | Pair a Bluetooth remote/controller |

The install and artwork recipes are safe to re-run. On an already configured
machine prefer `htpc-steam-freetube` over `htpc-steam-shortcut`; the latter is
the complete initial shortcut setup and may add duplicate Steam entries when
run repeatedly.

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
- **Leave Waydroid with the Steam button → Exit Game, never Android's own
  shutdown.** Powering Android off from the TV UI stops Android but leaves
  `cage` — the kiosk compositor the launcher wraps Waydroid in — running with no
  client. That is a black screen that no longer responds to the remote, because
  the thing the remote was talking to is gone. Steam treats
  `waydroid-launcher` as a running game, so *Exit Game* closes cage, and the
  launcher then stops the container itself. If you do end up on the black
  screen, `pkill cage` from a terminal is enough; a reboot is not needed.
- **SmartTube ships no x86_64 APK** (only arm64-v8a, armeabi-v7a, universal and
  32-bit x86). The Android TV image bundles ARM translation, which is what makes
  the arm64 build work here.
- **The back button** does not work when SmartTube is started via
  `waydroid app launch`. Start it from the Android TV launcher instead.
- **Widevine L3** caps DRM-protected content at 1080p. YouTube's ordinary
  streams are not Widevine-protected so 4K should be fine — but verify it rather
  than assume.
- **A Bluetooth remote cannot wake this box unless udev says so.** The Nvidia
  Shield remote's standby button suspends it happily, but nothing wakes it
  again: the USB Bluetooth adapter ships with `power/wakeup` set to `disabled`,
  so the keypress never reaches the sleeping host. Misleadingly, the PCI xHCI
  controller above it *is* wakeup-enabled out of the box, which makes the path
  look open when only the leaf device is shut out. The image now ships
  `90-htpc-bluetooth-wakeup.rules` to fix this; it only works because the
  machine suspends to `s2idle` (`cat /sys/power/mem_sleep`) — under S3 the
  adapter would lose power regardless.
- **The Shield remote's centre button does nothing in Steam Game Mode without
  a keymap fix.** It sends HID Consumer-Control usage `0x0041` ("AC Select"),
  which the kernel maps to `KEY_SELECT` — a real keycode, but not one
  gamescope's Steam UI treats as confirm (only Enter/Return is). The image
  ships `90-htpc-shield-remote.hwdb` to remap it to `KEY_ENTER`; this also
  fixes it in Kodi, whose default keymap never bound the `select` key name in
  the first place.
- **The remote's ◁ button sends `KEY_BACK`, which Steam Game Mode ignores.**
  Remapped to Escape in the same hwdb file, which is what that UI actually
  treats as back/cancel.
- **The remote's Netflix button launches Kodi**, via
  `htpc-shield-remote-macros.service` (a *user* service). It launches through
  `steam://rungameid/...` rather than `flatpak run`, so Steam owns the window
  exactly as if you had picked the Kodi tile — starting the flatpak directly
  leaves an unmanaged window beside gamescope and wedges Game Mode.
- **Kodi must have been started once** before `ujust htpc-xstreamflex` works; it
  needs `~/.var/app/tv.kodi.Kodi` to exist.
- **EmuDeck 2.5.0's Eden installer is broken.** Selecting Eden in Custom Install
  does not download it; the setup log reports `checkEdenBios: command not found`
  (an upstream bug, EmuDeck issue #1568). Workaround: download Eden's AppImage
  directly from https://git.eden-emu.dev/eden-emu/eden/releases (pick
  `-amd64-clang-pgo`), place it in `~/Applications/`, and `chmod +x` it.
- **Do not put Eden keys in `~/Emulation/bios/eden/`.** That folder is a dead
  end — Eden ignores it completely and reads from `~/.local/share/eden/keys/`
  instead. Placing files there will not be recognized.
- **Two `userConfigurations.json` files exist, and the template can silently
  overwrite the real one.** `~/.config/EmuDeck/backend/configs/steam-rom-manager/userData/userConfigurations.json`
  is EmuDeck's template; `~/.config/steam-rom-manager/userData/userConfigurations.json`
  is what Steam ROM Manager actually reads and writes. Fixing only the real
  one doesn't stick: opening Steam ROM Manager through EmuDeck's own
  menu/desktop entry runs an `rsync` (in `SRM_addExtraParsers()`,
  `~/.config/EmuDeck/backend/functions/ToolScripts/emuDeckSRM.sh`) that
  copies the template over the real file, undoing any manual fix or
  enable/disable change since. Fix **both** files' executor paths and
  `disabled` flags at once, or expect it to revert. Both shipped with broken
  paths for every emulator (one had a Steam Deck SD-card path,
  `/run/media/mmcblk0p1/...`; the other had `~/Emulation/tools/launchers/<emu>.sh`,
  which doesn't exist - the real scripts are at
  `~/.config/EmuDeck/backend/tools/launchers/`), and both had Citron and
  Ryujinx enabled with Eden disabled. Launching
  `~/Emulation/tools/Steam-ROM-Manager.AppImage` directly (or its CLI:
  `list` / `enable <id>` / `disable <id>` / `add` / `remove`) skips the rsync
  and is the reliable way to check or change state.
- **Steam does not notice `shortcuts.vdf` changing underneath it.** It reads
  the file once at startup and holds that in memory; edits made (by Steam ROM
  Manager or by hand) while Steam is already running only take effect after a
  full Steam restart, not just closing and reopening a window.

## The add-ons

Two add-ons of ours run inside Kodi's Flatpak, each from its own repository:

| Add-on | Repo | Gives you |
| --- | --- | --- |
| **xstreamflex** | [adriebaselmans/xstreamflex](https://github.com/adriebaselmans/xstreamflex) | Live TV (via IPTV Simple), plus films and series in Kodi's own library |
| **myTune** | [adriebaselmans/myTune](https://github.com/adriebaselmans/myTune) | Music from a self-hosted myTune server elsewhere on the LAN |

The exported library is **catalogue-sized on purpose**: ~5.5k films and ~2.4k
shows with ~55k episodes, or roughly 123k `.strm`/`.nfo` files and a 69 MB
`MyVideos*.db`. Kodi's library is built for a collection you own, so anything
that walks all of it (or all ~10k tags) is slow — see `CLAUDE.md`. Browsing the
same catalogue live through the add-on's own `plugin://` listings needs none of
those files; the full export is kept because it fills the Movies and TV Shows
menus, and that trade was chosen knowingly.

Metadata comes from the provider's per-item detail calls, not from an online
scraper: both sources are scanned with **Local information only**. Movie NFOs
carry plot, `<premiered>` (which is what lets Kodi offer "Release date" as a
sort order at all), genre, director, cast, runtime, fanart and a TMDB
`<uniqueid>`; titles are stripped of provider decorations like `4K` and `(NL)`
in `<title>` only — never in filenames, which keep the id that makes them
unique.

**xstreamflex works unmodified under Flatpak.** Every path derives from
`xbmcvfs.translatePath()` on the add-on profile, so it resolves to
`~/.var/app/tv.kodi.Kodi/data/...` — the `.strm`/`.nfo` library, the M3U export
and the IPTV Simple configuration all land inside the same sandbox Kodi reads
from. Nothing needs to reach outside it. The exception is putting the library
on a NAS or external disk; that needs filesystem permissions granted via
**Flatseal**, which is why Flatseal is in the image.

Two things worth knowing before hunting for settings that do not exist:

- **Live TV is filtered by country.** A full panel is ~11,800 channels, which
  gives Kodi an EPG large enough to wedge the UI. xstreamflex filters the export
  at the source; a second menu entry rebuilds across all countries when you need
  something the filter excludes.
- **Music cannot go into Kodi's library.** Kodi's music scanner reads tags
  embedded in audio files and cannot index `.strm` at all, so myTune is reached
  through **Music → Files** (add `plugin://plugin.audio.mytune/` as a music
  source) or through **Favourites** on the home screen. The **Music** tile
  itself always opens the empty music library. A Kodi limitation, not a missing
  setting — see [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#what-music-can-and-cannot-be).
