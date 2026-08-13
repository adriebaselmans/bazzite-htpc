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

Nobody has yet confirmed on the machine itself that **Waydroid works under Game
Mode**. Game Mode runs under `gamescope`; Waydroid wants its own Wayland session.
Standalone Waydroid on Bazzite is supported and documented, but SmartTube
launching *from within* Game Mode is untested. Fallback: run Waydroid from
Desktop Mode and keep Game Mode for games.

The 40 FPS suggestion for demanding Cemu titles comes from EmuDeck's docs, not
from a measurement on this hardware.

## Working style the user asked for

Verify fast-moving external facts online rather than answering from memory —
app/distro support, API quotas, hardware compatibility, package availability.
This project has already produced several cases where a memory-based answer was
materially wrong and a search reversed the recommendation.
