# Wii U emulation (Cemu) via EmuDeck, alongside the existing HTPC setup.
#
# EmuDeck is installed through bazzite-portal, which ships with Bazzite itself -
# no custom installer here. EmuDeck then owns the whole emulation stack: it
# installs Cemu, creates ~/Emulation, and bundles its own Steam ROM Manager.
#
# Because it owns that stack, this image deliberately does NOT also ship Cemu or
# Steam ROM Manager as flatpaks. Installing both gives you two Cemus and two
# SRMs with separate configs, which is how duplicate Steam shortcuts happen.
#
# Note on trust: EmuDeck installs Cemu as an AppImage. In May 2026 Cemu's
# AppImage and Ubuntu zip release assets were replaced with a credential stealer
# via an account with no prior contribution to the repo; Windows, macOS and the
# Flathub Flatpak were untouched. Those assets have since been restored. The
# Flatpak channel remains the safer one, but EmuDeck does not support it yet
# (dragoonDorise/EmuDeck#1140) - this is a deliberate, informed trade-off for
# EmuDeck's integration.

EMU_ROOT := "$HOME/Emulation"

# Install EmuDeck via Bazzite's own portal, then point at the follow-up steps.
setup-emulation:
    #!/usr/bin/bash
    set -euo pipefail

    if [[ -d "{{EMU_ROOT}}" ]]; then
        echo "==> {{EMU_ROOT}} already exists - EmuDeck looks installed."
        echo "    Re-running the portal is safe; it will not wipe your ROMs."
        echo ""
    fi

    if ! command -v bazzite-portal >/dev/null 2>&1; then
        echo "bazzite-portal is not available on this image." >&2
        echo "It ships with Bazzite itself, so this is unexpected - check that" >&2
        echo "you are running the bazzite-deck base rather than something else." >&2
        exit 1
    fi

    echo "Opening Bazzite Portal. Pick EmuDeck, then in EmuDeck's own setup:"
    echo "  - choose Custom install if you want to pick emulators individually"
    echo "  - enable Cemu"
    echo "  - point storage at your preferred drive (default is fine)"
    echo ""
    echo "Afterwards:"
    echo "  ujust emulation-paths   where everything lives"
    echo "  ujust emulation-tune    performance settings for the 780M"
    echo "  ujust emulation-steam   getting games into Steam"
    echo ""
    bazzite-portal

# Print where EmuDeck keeps ROMs, Cemu config, keys and saves.
emulation-paths:
    @echo "EmuDeck installs Cemu natively (AppImage), so these are the native paths:"
    @echo ""
    @echo "  your game dumps          {{EMU_ROOT}}/roms/wiiu/roms"
    @echo "  saves / persistent data  {{EMU_ROOT}}/roms/wiiu/mlc01"
    @echo "  config + controllers     ~/.config/Cemu/"
    @echo "  graphic packs + shaders  ~/.local/share/Cemu/"
    @echo "  keys.txt (encrypted ROMs) ~/.local/share/Cemu/"
    @echo "  EmuDeck itself           {{EMU_ROOT}}/tools/"
    @echo ""
    @echo "Prefer decrypted dumps (.wua / .rpx) - Cemu is moving away from"
    @echo "encrypted .wud/.wux. Provide your own; nothing ships here."

# Performance checklist for the Radeon 780M. Deliberately not automated.
emulation-tune:
    @echo "Apply these in Cemu once (Options > General settings / Graphics):"
    @echo ""
    @echo "  Graphics API            Vulkan"
    @echo "  Graphics device         Radeon 780M"
    @echo "  VSync                   On  (HTPC on a TV - tearing is worse than a"
    @echo "                              frame of latency, and it caps the iGPU)"
    @echo "  Async shader compile    On  (the big one: without it you get a"
    @echo "                              stutter at every new shader)"
    @echo "  Accurate barriers       On  (leave default; off risks glitches)"
    @echo "  Full sync at GX2DrawDone  Off"
    @echo ""
    @echo "Per-game, via Graphic Packs:"
    @echo "  - resolution 1920x1080; do not exceed the TV's native resolution"
    @echo "  - demanding titles (e.g. Breath of the Wild) run steadier at a"
    @echo "    40 FPS cap than chasing 60 and missing it"
    @echo ""
    @echo "Not written automatically on purpose: a malformed settings.xml stops"
    @echo "Cemu from starting, and overwriting an existing one would discard"
    @echo "controller profiles you had already set up."

# How to get Wii U games into Steam with artwork.
emulation-steam:
    @echo "Use the Steam ROM Manager that EmuDeck installed - not a separate one."
    @echo "Launch it from the EmuDeck app (Tools > Steam ROM Manager)."
    @echo ""
    @echo "  1. Close Steam completely first. SRM edits Steam's shortcuts file;"
    @echo "     with Steam running, your new entries are discarded on exit."
    @echo "  2. Parser: 'Nintendo WiiU - Cemu (.wua) - Native' or the .rpx"
    @echo "     variant, matching your dump format."
    @echo "  3. Test Parser, check the titles and artwork, then Parse + Save."
    @echo "  4. Back in Game Mode the games appear as normal Steam entries."
    @echo ""
    @echo "Never enable Proton compatibility on Cemu or on the games SRM adds:"
    @echo "this is a native Linux build and Proton breaks it."
