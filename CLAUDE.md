# bazzite-htpc — context for Claude

A custom Bazzite image turning a mini-PC into a living-room box: HTPC (Kodi with
the `xstreamflex` IPTV add-on, SmartTube via Waydroid) plus Wii U emulation
(Cemu via EmuDeck), with Steam Game Mode as the shell.

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

**EmuDeck over the Flathub Cemu Flatpak.** The user chose this deliberately after
being told that Cemu's AppImage and Ubuntu zip release assets were replaced with
a credential stealer in May 2026 (Flatpak was untouched, assets since restored).
EmuDeck does not support a Flatpak Cemu yet. Do not quietly revisit this; it was
an informed trade-off.

**No Cemu or Steam ROM Manager flatpaks in the image.** EmuDeck installs both.
Shipping duplicates causes duplicate Steam shortcuts.

**Performance settings are a printed checklist, not a generated `settings.xml`.**
A malformed one stops Cemu starting; overwriting an existing one discards
controller profiles.

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

The one thing left unmeasured is Cemu. The 40 FPS suggestion for demanding Cemu titles comes from EmuDeck's docs,
calibrated to Steam Deck's (RDNA2, 8 CU) iGPU, not from a measurement on this
hardware. The Radeon 780M is the same RDNA3, 12-CU silicon as the Ryzen Z1
Extreme's iGPU (ROG Ally), which comfortably outperforms Steam Deck in Cemu
workloads — so the real ceiling here is probably above 40 FPS on demanding
titles. But Cemu/BOTW performance is also cache- and CPU-bound, not just GPU,
so treat this as "likely better" rather than a revised number until measured.

## Working style the user asked for

Verify fast-moving external facts online rather than answering from memory —
app/distro support, API quotas, hardware compatibility, package availability.
This project has already produced several cases where a memory-based answer was
materially wrong and a search reversed the recommendation.
