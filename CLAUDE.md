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

- **Steam ROM Manager may inherit broken Steam-Deck-paths after EmuDeck setup.**
  EmuDeck pre-generates parser configs in `~/.config/EmuDeck/backend/configs/steam-rom-manager/userData/userConfigurations.json`
  with hardcoded executor paths like `/run/media/mmcblk0p1/Emulation/tools/launchers/`
  — a Steam Deck's SD-card mount point, not the correct `~/.config/EmuDeck/backend/tools/launchers/`.
  This breaks all 23 emulator entries (not just Eden). If games fail to launch after
  setup, edit that JSON file directly to replace the broken prefix.

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
