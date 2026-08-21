# How this machine actually fits together

A reference for the living-room box: which layer owns what, where every piece
of state really lives, and the Flatpak/Steam mechanics that repeatedly turn out
to matter. [README.md](../README.md) is the install path; this is the map you
want open when something behaves strangely.

## Three repositories

| Repo | Is | Ships as |
| --- | --- | --- |
| **bazzite-htpc** (this one) | The OS image and the `ujust` recipes | A signed OCI image; `rpm-ostree` pulls it |
| **[xstreamflex](https://github.com/adriebaselmans/xstreamflex)** | Kodi add-on: IPTV live TV, VOD and series from an Xtream Codes panel | A Kodi add-on ZIP, installed by `ujust htpc-xstreamflex` |
| **[myTune](https://github.com/adriebaselmans/myTune)** | Self-hosted music server (Node/Docker) **plus** a Kodi add-on that streams from it | Server runs elsewhere on the LAN; add-on installed by hand |

They are separate repos because they have separate lifecycles: the image
changes rarely, the add-ons change often, and myTune's server does not run on
this machine at all. What binds them is that **both add-ons live inside Kodi's
Flatpak**, which is where most of the surprises come from.

## Four storage layers

The single most useful thing to internalise: state lives in four places with
very different rules, and a change in the wrong one silently disappears.

| Layer | Path | Survives reinstall? | Written by |
| --- | --- | --- | --- |
| **Image** (`/usr`) | read-only ostree | Yes — it *is* the image | `recipes/recipe.yml`, rebuilt by CI |
| **Flatpak app** | `/var/lib/flatpak/app/<id>/…` | Reinstalled by the image's flatpak list | `flatpak update` |
| **Flatpak app data** | `~/.var/app/<id>/data/` | **No** | The app itself |
| **Plain `$HOME`** | `~/.local`, `~/.config`, `~/Emulation` | **No** | Everything else |

`/usr` being read-only is why anything user-specific has to be a `ujust`
recipe rather than a file in the image: Waydroid downloads Android images at
init time, Steam keeps its shortcuts in `$HOME`, and Flatpak keeps overrides
under `/var`. None of that can be baked in. That is the whole reason
`files/justfiles/` exists.

## Where things actually live

### Kodi and its add-ons

Kodi is a Flatpak, so it has a read-only application and a separate writable
data directory. Everything you care about is in the second one.

| What | Path |
| --- | --- |
| Kodi application (read-only) | `/var/lib/flatpak/app/tv.kodi.Kodi/…/files/` |
| Kodi's home (`special://home`) | `~/.var/app/tv.kodi.Kodi/data/` |
| Installed add-ons | `…/data/addons/` |
| Per-add-on settings and state | `…/data/userdata/addon_data/<addon.id>/` |
| Databases (EPG, video library, textures) | `…/data/userdata/Database/` |
| Log | `…/data/temp/kodi.log` |
| Bundled add-ons Kodi ships itself | `/var/lib/flatpak/app/tv.kodi.Kodi/…/files/share/kodi/addons/` |

That last row matters more than it looks: `pvr.iptvsimple` and the joystick
peripheral add-on are **inside the Flatpak**, not downloaded. Their default
button maps and settings schemas are there, read-only, and a user override goes
in `addon_data/` alongside.

Add-ons can be installed by copying a directory straight into `…/data/addons/`.
That is what `ujust htpc-xstreamflex` does, and it sidesteps Kodi's rule that a
ZIP must carry a higher version number than what is installed. Kodi runs
`addon.py` fresh for every single plugin invocation, so replacing the files
takes effect on the next navigation — no restart needed for code changes.
`addon.xml` changes do need a restart.

> **Never keep a backup copy inside `…/data/addons/`.** Kodi scans that
> directory and reads the add-on id from each `addon.xml`, not from the folder
> name. A `plugin.audio.mytune.bak-1787296354/` sitting next to the real thing
> is a second registration of the same id, and Kodi may well pick *it* — the
> log then shows it invoking `…mytune.bak-…/addon.py` while every edit you make
> to the real directory appears to do nothing. Put backups somewhere else
> entirely (`~/kodi-addon-backups/`), and note that removing the stray copy is
> not enough on its own: Kodi holds the resolved path in memory until it
> restarts.

### The Flatpak sandbox, concretely

Kodi's sandbox has **no access to your home directory**. Its permissions are
`/mnt`, `/media`, `/run/media`, `xdg-videos`, `xdg-music`, `xdg-pictures`,
`/run/lirc`, `/run/udev:ro` and `devices=all` — check with
`flatpak info --show-permissions tv.kodi.Kodi`.

Consequences that have actually bitten:

- **A path like `/home/adrie/whatever` is invisible to Kodi.** Adding a video
  source there fails. Anything Kodi must read has to be under its own data
  directory, or under one of the granted paths.
- xstreamflex works unmodified precisely because every path it uses derives
  from `xbmcvfs.translatePath()` on the add-on profile, which resolves inside
  the sandbox. Its `.strm`/`.nfo` library, the M3U export and the IPTV Simple
  configuration all land in the same place Kodi reads from.
- Putting a media library on a NAS or external disk needs an explicit grant.
  That is why **Flatseal** is in the image.

**Overrides** change a Flatpak's environment or permissions from outside:

```bash
flatpak override --user --unset-env=LC_ALL tv.kodi.Kodi   # what ujust htpc-kodi-locale does
flatpak override --user --show tv.kodi.Kodi               # inspect
```

They are stored in `~/.local/share/flatpak/overrides/<app-id>` (user) or
`/var/lib/flatpak/overrides/` (system) — both under mutable state, neither
carried by the image, which is why the locale fix is a `ujust` recipe.

### Steam, which is the shell

Steam Game Mode is the boot target, so Steam owns the home screen and launches
everything else.

| What | Path |
| --- | --- |
| Non-Steam shortcuts | `~/.local/share/Steam/userdata/<id>/config/shortcuts.vdf` (binary) |
| Tile artwork | `~/.local/share/Steam/userdata/<id>/config/grid/` |

`shortcuts.vdf` is a **binary** VDF, editable with the `vdf` Python module
(present system-wide). Two rules, both learned the hard way:

- **Steam reads it once at startup** and holds it in memory. Editing it while
  Steam runs achieves nothing visible, and Steam overwrites your edit when it
  exits. Close Steam first.
- Artwork is keyed by the shortcut's **unsigned 32-bit** app id, while
  `shortcuts.vdf` stores it signed. Convert with `appid & 0xFFFFFFFF`.

Grid artwork comes in several flavours and they are not interchangeable — the
icon you set in Properties is *not* what the Game Mode tile shows:

| File | Purpose | Size used here |
| --- | --- | --- |
| `<appid>.png` | Horizontal capsule (the grid tile) | 920×430 |
| `<appid>p.png` | Portrait capsule | 600×900 |
| `<appid>_logo.png` | Logo overlay (transparent) | 471×375 |
| `<appid>_hero.png` | Banner behind the detail page | 3840×1240 |
| `<appid>_icon.png` | Small icon (lists, Properties) | 256×256 |

**Steam exports `LC_ALL=C` to everything it launches**, and `LC_ALL` beats
`LANG`. Every app started from a tile inherits it — Kodi, Waydroid, Eden. For
anything Python-based that means an ASCII filesystem encoding, so a filename
containing an accent cannot be written at all. Check with:

```bash
tr '\0' '\n' < /proc/$(pgrep -x kodi.bin)/environ | grep LC_ALL
```

### Emulation, Waydroid, and the rest

| What | Path |
| --- | --- |
| Waydroid system config and images | `/var/lib/waydroid/` |
| Waydroid Android userdata | `~/.local/share/waydroid/data/` (root-owned subdirs) |
| EmuDeck | `~/Emulation/`, config in `~/.config/EmuDeck/` |
| EmuDeck launcher scripts (the real ones) | `~/.config/EmuDeck/backend/tools/launchers/` |
| Eden emulator | `~/Applications/` (AppImage) |
| Eden config / keys / firmware | `~/.config/eden/`, `~/.local/share/eden/` |
| Steam ROM Manager | `~/Emulation/tools/Steam-ROM-Manager.AppImage` |

Two traps encoded in that table. Eden ignores EmuDeck's `~/Emulation/bios/eden/`
folder completely and uses its own XDG paths. And Steam ROM Manager keeps its
real configuration in `~/.config/steam-rom-manager/userData/`, while EmuDeck
holds a *template* copy that it rsyncs over the real one whenever SRM is
launched from EmuDeck's menu — fix both or the fix reverts. Full detail in
[CLAUDE.md](../CLAUDE.md#traps-that-cost-real-time-here).

## Diagnostics

### Is it the add-on, or is it Kodi?

Kodi's JSON-RPC listens on **port 9090** and answers regardless of what the UI
is doing — unless Kodi's main thread is wedged, in which case nothing answers.
That distinction saves hours:

```bash
python3 -c "
import json,socket
s=socket.create_connection(('127.0.0.1',9090),timeout=5)
s.sendall(json.dumps({'jsonrpc':'2.0','id':1,'method':'JSONRPC.Ping'}).encode())
s.settimeout(10); print(s.recv(4096))"
```

No answer means stop debugging the add-on — Kodi itself is stuck, and whatever
you opened last is a victim, not the cause. A wedged Kodi shows as ~80% CPU on
the main thread with almost no I/O:

```bash
P=$(pgrep -x kodi.bin); ps -o stat,%cpu -p $P; cat /proc/$P/io
```

You can also drive a plugin directly, which is the fastest way to reproduce a
listing failure without touching the remote:

```bash
python3 -c "
import json,socket
s=socket.create_connection(('127.0.0.1',9090),timeout=5)
s.sendall(json.dumps({'jsonrpc':'2.0','id':1,'method':'Files.GetDirectory',
  'params':{'directory':'plugin://plugin.audio.mytune/?action=albums'}}).encode())
s.settimeout(45); print(s.recv(200000)[:400])"
```

Debug logging can be toggled live over the same channel
(`Settings.SetSettingValue`, setting `debug.showloginfo`) — it also puts an FPS
and memory overlay on screen, so turn it back off.

### Kodi's own settings definitions can be the bug

An add-on's `resources/settings.xml` is parsed by Kodi, and Kodi is strict in
ways that fail *silently from the add-on's point of view*. A string setting
that defaults to empty needs both halves:

```xml
<default></default>
<constraints>
  <allowempty>true</allowempty>
</constraints>
```

Without the constraint — or with `<default>` omitted entirely, which fails the
same way — Kodi logs `error reading the default value of "username"` and never
registers the setting. `getSettingString()` then raises
`TypeError: Invalid setting type` instead of returning `""`, so any add-on code
reading it dies on every invocation. The bundled `pvr.iptvsimple` is a good
reference for the working spelling.

Worth checking early: those `CSettingString` errors appear at add-on load, well
before whatever symptom you are chasing.

### Controllers: Steam Input duplicates every press

A controller used inside an app launched from a Steam tile reaches that app
**twice**: once as the real device, and once as the virtual pad Steam Input
creates (vendor `28de`, Valve). In Kodi that shows up as every d-pad press or
stick flick moving two items instead of one.

Confirmed by counting raw events on both nodes while pressing:

```bash
ls /dev/input/js*                       # two nodes = two devices
grep -iE 'N: Name=.*(xbox|pad|controller)' /proc/bus/input/devices
```

Kodi's log lists both under `new joystick device registered`. Deleting the
phantom's button map does **not** help — a built-in or family map still
matches it, and an empty override map does not suppress it either.

The fix is on Steam's side: select the tile, **Manage → Controller settings**,
and disable Steam Input for that shortcut. The virtual pad then stops existing
and Kodi sees one device. There is no field for this in `shortcuts.vdf` —
Steam keeps per-game controller configuration in its own cloud-synced store,
so this is a UI step, not something a script can set.

Related, for the real controller: Kodi matches a button map on **name plus
button count plus axis count**. The bundled
`Xbox_Wireless_Controller_15b_9a.xml` declares 9 axes while a Bluetooth Xbox
pad reports 8, so it never matches and the controller does nothing at all. A
user copy in
`addon_data/peripheral.joystick/resources/buttonmaps/xml/linux/` with the
correct count fixes it; every axis index the bundled map uses (0-7) fits in 8
axes, so nothing else needs changing.

### What music can and cannot be

Kodi's **music** library indexes tags embedded in audio files, so it cannot
scan `.strm` files at all. That is why xstreamflex can put films and series
into Kodi's native video library via `.strm` + `.nfo`, while myTune cannot do
the same for music — the video scanner accepts `.strm`, the music scanner does
not. It is a Kodi limitation, not a missing setting.

The practical consequences: the **Music** home tile always opens the (empty)
music library, and streaming music add-ons are reached through
**Music → Files** (add `plugin://plugin.audio.mytune/` as a music source) or
through **Favourites**, which Estuary can surface on the home screen. Estuary's
home buttons are individually hideable via
`addon_data/skin.estuary/settings.xml` (`homemenuno<section>button`).

### When an add-on fails but logs nothing

`script successfully run` in `kodi.log`, immediately followed by
`GetDirectory - Error`, with no traceback and no add-on log line, means the
add-on's own error reporting broke. Both add-ons here have hit this, for
different reasons, and both now guard against it — but if you see that
signature in a *new* add-on, the fastest move is a temporary raw
`xbmc.log(...)` probe at the top of the failing function. `xbmc.log` depends on
nothing and always reaches the log.

### Logs worth knowing

| What | Where |
| --- | --- |
| Kodi | `~/.var/app/tv.kodi.Kodi/data/temp/kodi.log` |
| Waydroid daemon | `/var/lib/waydroid/waydroid.log` |
| Waydroid Android | `sudo waydroid logcat` (needs root) |
| EmuDeck | `~/.config/EmuDeck/logs/` |
| Steam ROM Manager | `~/.config/steam-rom-manager/logs/main.log` |
| Eden | `~/.local/share/eden/log/eden_log.txt` |

## Scale, and why it matters here

The IPTV panel this was built against serves **~11,800 channels in 262
groups**. Handing all of them to IPTV Simple gave Kodi an EPG of ~80,000
entries in a 45 MB database, which was enough to wedge the UI after zapping
through a few channels and to make shutdown take minutes.

xstreamflex therefore filters the channel export by country code (~570 channels
here) — at the source, not in Kodi's settings, so the scheduled 6-hourly export
cannot quietly undo it. A second menu entry rebuilds across all countries when
you need something the filter excludes. The VOD/series sync has always filtered
this way; the channel export catching up is what closed the gap.

If Kodi ever becomes sluggish again after this, suspect the *number of
simultaneous streams* rather than the catalogue size: opening several live
channels in quick succession is what actually wedged the main thread, and a
provider connection limit is the likely mechanism.
