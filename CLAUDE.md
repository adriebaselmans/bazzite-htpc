# bazzite-htpc — context for Claude

A custom Bazzite image turning a mini-PC into a living-room box: HTPC (Kodi with
the `xstreamflex` IPTV add-on, SmartTube via Waydroid) plus Nintendo Switch
emulation (Eden via EmuDeck), with Steam Game Mode as the shell.

Built to replace an ageing NVIDIA Shield that had to be rebooted to keep
streaming. Read `README.md` first — it carries the install path and the traps.

## Hardware

AMD Ryzen 7 H255, Radeon 780M iGPU, 16 GB dual-channel, on a TV.

The AMD part is load-bearing: Waydroid does not work on Nvidia at all, which
would take SmartTube with it. Never suggest an `-nvidia` base image variant.

## Structure

- `recipes/recipe.yml` — BlueBuild recipe. Base is `ghcr.io/ublue-os/bazzite-deck`
  (the Handheld/HTPC variant that boots into Game Mode).
- `files/justfiles/*.just` — shipped as `ujust` commands. This is where anything
  that cannot live in an image goes: Waydroid downloads Android images at init
  time, and Steam/Kodi config lives in `$HOME`.
- GitHub Actions builds and signs on push; `rpm-ostree upgrade` pulls it.

## Decisions worth not re-litigating

**Flatpak over `rpm-ostree` layering.** Bazzite's docs call layering a last
resort — it can block OS upgrades until the package is removed.

**No emulator or Steam ROM Manager flatpaks in the image.** EmuDeck installs
both. Shipping duplicates causes duplicate Steam shortcuts.

## Traps that cost real time here

- **Never use the `a16-tv` (Android 16) Waydroid image on this stack.** Android
  16 requires the `aidl6` servicemanager protocol; the host's libgbinder
  (1.1.43 on Fedora 43) only implements `Aidl`…`Aidl4`, and waydroid 1.6.2's
  `protocol.py` maps everything ≥ API 33 to `aidl3` anyway. The failure looks
  like a slow boot and is not one: the container reports RUNNING, but every
  waydroid command prints `Failed to get service waydroidplatform` forever
  because the host is speaking a protocol the image's servicemanager does not
  answer. No `waydroid.cfg` edit fixes it. `a13-tv` (LineageOS 20 / API 33) is
  the working choice; verify with
  `strings /usr/lib64/libgbinder.so.1 | grep Aidl` before ever bumping it.
- **Changing Android version means wiping `~/.local/share/waydroid/data`.**
  `waydroid init -f` replaces the images but keeps the userdata, so a downgrade
  boots Android 13 on Android 16's data and hangs before it even gets a DHCP
  lease (`IP address: UNKNOWN` in `waydroid status` is the tell). The wipe needs
  root — the subdirectories are owned by Android UIDs.
- **A wedged Android boot can also be one ANR-looping app.** On the a16 image the
  TV setup wizard (`com.google.android.tungsten.setupwraith`) ANR'd, crashed and
  restarted every ~6s, which kept `system_server` permanently busy. The tell in
  `logcat` is a long run of `ActivityManager: Collecting stacks for native pid …`
  — that is Watchdog dumping every process, not a boot in progress. Fix is
  `pm disable <pkg>` from `waydroid shell`, never uninstall (that black-screens).

- **Android's own shutdown is not the way out of Waydroid.** The launcher wraps
  Waydroid in `cage`; powering Android off from the TV UI leaves cage running
  with no client, which presents as a black screen that ignores the remote. The
  exit is Steam button → Exit Game (Steam owns `waydroid-launcher` as a running
  game, and the launcher stops the container once cage dies). `pkill cage`
  recovers it without a reboot.

- **EmuDeck 2.5.0's Eden installer is broken.** The Custom Install flow does not
  actually download Eden when selected; the backend logs show `checkEdenBios:
  command not found`, a function EmuDeck's own code calls but never defines
  (upstream issue dragoonDorise/EmuDeck#1568, marked "Planned for 3.x"). The
  fix is to download Eden's AppImage directly from
  https://git.eden-emu.dev/eden-emu/eden/releases (pick the `-amd64-clang-pgo`
  build, not `-steamdeck-` or `-rog-ally-`), place it in `~/Applications/`,
  and `chmod +x` it — EmuDeck's launcher scripts already search that folder.

- **Eden's config does not live in `~/Emulation/bios/eden/`.** That folder is a
  dead end; Eden ignores it completely. Keys belong in `~/.local/share/eden/keys/`
  (as `prod.keys` and `title.keys`), and firmware lands in `~/.local/share/eden/nand/`
  after being imported through Eden's own settings UI. Files placed in the EmuDeck
  bios folder are simply never read — this was confirmed both by the missing
  `checkEdenBios` function above and by direct testing (keys in the EmuDeck folder
  were not recognized; the same emulator launched directly and configured through
  its own UI worked immediately).

- **Steam ROM Manager has two config files, and the template can silently
  overwrite the real one - fix both, always.**
  `~/.config/EmuDeck/backend/configs/steam-rom-manager/userData/userConfigurations.json`
  is EmuDeck's template; `~/.config/steam-rom-manager/userData/userConfigurations.json`
  (different inode) is what Steam ROM Manager actually reads and writes.
  Editing only the real one is not durable: `SRM_addExtraParsers()` in
  `~/.config/EmuDeck/backend/functions/ToolScripts/emuDeckSRM.sh` runs an
  `rsync` from the template onto the real file (with a timestamped `.bak`)
  every time Steam ROM Manager is launched through EmuDeck's own menu/desktop
  entry, silently reverting any manual fix or enable/disable change made
  since. Both copies shipped with broken executor paths for all 23 emulator
  entries (the template had `/run/media/mmcblk0p1/...`, a Steam Deck SD-card
  mount; the real one had `/home/adrie/Emulation/tools/launchers/<emu>.sh`,
  which doesn't exist - the real launcher scripts live at
  `~/.config/EmuDeck/backend/tools/launchers/`), and both had Citron and
  Ryujinx enabled with Eden disabled. Fix both files' paths and `disabled`
  flags together, or the next EmuDeck-launched Steam ROM Manager session
  undoes it. Launching the AppImage directly (`~/Emulation/tools/Steam-ROM-Manager.AppImage`,
  or its CLI: `list` / `enable <id>` / `disable <id>` / `add` / `remove`)
  skips this rsync entirely and is the more reliable way to check state.

- **Steam exports `LC_ALL=C` to everything it launches, and `LC_ALL` beats
  `LANG`.** Every app started from a Steam shortcut on this box - Kodi,
  Waydroid, Eden - inherits it. For anything Python-based that means an ASCII
  filesystem encoding, so a media title with an accent cannot be written as a
  filename at all. It surfaced as xstreamflex's library sync aborting with
  `'ascii' codec can't encode characters in position 116-122`, which looks like
  an add-on bug and is not one. Check with
  `tr '\0' '\n' < /proc/$(pgrep -x kodi.bin)/environ | grep LC_ALL`.
  `ujust htpc-kodi-locale` clears it for Kodi via a flatpak override; that
  override lives in mutable state under `/var`, which is why it is a `ujust`
  step and not something the image can carry.
- **Kodi's main thread can wedge on live TV, and it looks like something else
  broke.** Zapping through a few IPTV channels left `kodi.bin` spinning at ~80%
  CPU with no I/O, unresponsive even to a bare `JSONRPC.Ping` over port 9090 -
  so the next add-on opened just sat there, which is what gets noticed and
  blamed. That JSON-RPC ping is the fastest way to tell "this add-on hangs"
  from "Kodi hangs": if Ping does not answer, stop debugging the add-on. The
  underlying load was an 11.8k-channel playlist; xstreamflex now filters the
  export by country (~570 channels here), which is fixed at the source rather
  than in Kodi's settings.
- **A Bluetooth remote cannot wake this box from suspend by default, and the
  wakeup flags lie about why.** The Nvidia Shield remote's standby button
  suspends the machine, then nothing brings it back. The tell is
  `cat /sys/bus/usb/devices/*/power/wakeup`: the Realtek Bluetooth adapter
  (`0bda:b85b`, USB class `e0/01/01`) reads `disabled` while the PCI xHCI
  controller above it reads `enabled` - so the path looks open when only the
  leaf device is shut out. Fixed in the image by
  `files/system/usr/lib/udev/rules.d/90-htpc-bluetooth-wakeup.rules`, which
  matches on the USB class rather than on this specific chip. It only works
  because this box suspends to `s2idle` (`/sys/power/mem_sleep`); under S3 the
  adapter loses power and no flag helps.
- **The README's old claim that Shield remote pairing is lost across reboots
  did not hold here.** It pairs, bonds and trusts normally over BlueZ
  (`48:B0:2D:38:B2:4E`, `usb:v0955p7217`) and binds as a *single* HID keyboard -
  no second device doubling every press, unlike a gamepad under Steam Input.
  The circulating "known issue" is about pairing to a Shield, not to a Linux
  host. Verified across a full reboot (2026-08-22), not just suspend/resume.
- **The Shield remote's centre button is `KEY_SELECT`, and Steam Game Mode's
  UI navigation does not treat that as confirm.** D-pad works immediately
  (plain arrow keys), but the centre button does nothing there even though
  it's a real, correctly-generated keycode — confirmed via `evtest`: raw HID
  scancode `0xc0041` (Consumer-Control "AC Select"), evdev `KEY_SELECT` (code
  353). gamescope's keyboard-nav only confirms on Enter/Return. Fixed with a
  `hwdb` remap (`90-htpc-shield-remote.hwdb`,
  `evdev:input:b0005v0955p7217e0002*` → `KEYBOARD_KEY_c0041=enter`), scoped to
  this exact device by its full MODALIAS. Verified this does not regress
  Kodi: its default `keyboard.xml` has no `<select>` binding at all, only
  `<return>`/`<enter>` (both already mapped to the Select action) — so the
  button did nothing in Kodi either before this fix.
- **Anything the remote launches must go through Steam, not the app directly.**
  The Netflix button first launched Kodi with `flatpak run` and that wedged the
  box: in Game Mode gamescope is the shell and Steam owns the windows, so a
  bare flatpak lands next to gamescope with nothing managing it. Same class of
  failure as the reverted `post_gamescope_start` hook and the Waydroid/cage
  black screen. The fix is `steam://rungameid/<id>`, which makes the button
  behave exactly like selecting the tile. Resolve the id from `shortcuts.vdf`
  at runtime - `ujust htpc-steam-shortcut` rewrites that file and issues a new
  appid, so a hardcoded one silently stops working.
- **"Is it running yet?" is not a usable launch guard.** A `pgrep kodi.bin`
  check looks sufficient and is not: Steam (or flatpak) needs several seconds
  before anything is observable, so every press inside that window passes the
  check. Four impatient presses started four Kodis fighting over the display -
  the remote died and even Alt+F3 could not reach a TTY. Debounce on a
  monotonic clock instead, and keep the process check only as a second net.
- **A user service, not a system one, for anything that launches an app.**
  Starting a flatpak from a root service and dropping privileges to the user
  fails inside the sandbox with `bwrap: Can't find source path
  /run/user/1000/doc/by-app/tv.kodi.Kodi: Permission denied` - the document
  portal rejects a caller with no real session behind it. Reading the remote's
  evdev node as the user needs `91-htpc-shield-remote-uaccess.rules`; note that
  `TAG+="uaccess"` alone does *not* work here, because logind only grants that
  ACL for devices bound to a seat and this one lives under
  `/devices/virtual/misc/uhid`. Setting `OWNER=` is what actually works.
- **Every line of a just recipe must stay indented.** An unindented heredoc ends
  the recipe body; just then parses the embedded script as just syntax and
  reports a syntax error pointing at the script, not at the real cause.
- `justfiles.validate` is a **formatting** gate (`just --fmt --check`), not a
  syntax one. It fails working justfiles. Left off deliberately.
- **The first rebase must be `ostree-unverified-registry:`** — a stock Bazzite
  install cannot verify an image signed with this repo's key until that key is
  installed, which is what the first rebase does.
- **cosign signs the platform manifest by default, but rpm-ostree verifies the
  index.** If signing has to be done by hand, sign the index digest explicitly
  or the machine reports "A signature was required".
- The build pushes *before* it signs. If signing fails, `:latest` is updated but
  unsigned and the machine cannot upgrade. Re-run the workflow.

## Still unverified

**The Waydroid path is fully verified on this machine** (2026-08-13), end to
end: container boots, `waydroidplatform` resolves, SmartTube installs, its
**arm64** build executes under the image's ARM translation layer, and the Steam
tile launches the Android TV home screen **from Game Mode** with SmartTube
working from there. Nothing about this stack is speculative any more — see the
traps above for what it cost to get here.

Two mechanics worth keeping, since forum posts get both wrong:
`/usr/bin/waydroid-launcher` runs Waydroid inside `cage`, a kiosk compositor
that nests happily under gamescope, and its four `pkexec` calls are covered by
`/usr/share/polkit-1/rules.d/30-waydroid.rules` (wheel → YES), so nothing
prompts for a password. The launcher also **does** take arguments — with none
it runs `show-full-ui`, otherwise it `exec waydroid "$@"` — so
`waydroid-launcher app launch org.smarttube.stable` is a legitimate one-tap
Steam target. The default shortcut stays the plain launcher anyway, because
SmartTube started via `app launch` has the broken back button documented in the
README.

Eden performance on this hardware (Radeon 780M / Ryzen 7 H255) has not been
measured.

## Working style the user asked for

Verify fast-moving external facts online rather than answering from memory —
app/distro support, API quotas, hardware compatibility, package availability.
This project has already produced several cases where a memory-based answer was
materially wrong and a search reversed the recommendation.
