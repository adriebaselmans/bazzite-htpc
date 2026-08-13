# Wii U emulation (Cemu) alongside the existing HTPC setup.
#
# Cemu comes from Flathub rather than EmuDeck's AppImage install. EmuDeck is the
# established route and is otherwise fine, but its Cemu path is the AppImage,
# and in May 2026 Cemu's AppImage and Ubuntu zip release assets were replaced
# with a credential stealer via a stolen maintainer token. Windows, macOS and
# Flatpak were untouched. That channel is restored now, but Flathub builds and
# signs its own binaries, which suits an immutable host better either way.
#
# Nothing here writes Cemu's own settings: see `emulation-tune` for why the
# performance tuning is a checklist rather than a generated config.

EMU_ROOT := "$HOME/Emulation"
CEMU_ID := "info.cemu.Cemu"
SRM_ID := "com.steamgriddb.steam-rom-manager"

# Set up Wii U emulation: directories, sandbox access, and next steps.
setup-emulation: emulation-dirs emulation-permissions
    @echo ""
    @echo "Ready. Remaining steps, in order:"
    @echo "  1. Put your own decrypted dumps in {{EMU_ROOT}}/roms/wiiu/roms"
    @echo "     (.wua or .rpx - Cemu is moving away from encrypted .wud/.wux)"
    @echo "  2. Encrypted dumps also need keys.txt - run 'ujust emulation-paths'"
    @echo "  3. Apply the performance settings: ujust emulation-tune"
    @echo "  4. Add the games to Steam:         ujust emulation-steam"

# Create the ROM/data directory structure. Never deletes anything.
emulation-dirs:
    #!/usr/bin/bash
    set -euo pipefail

    for dir in "{{EMU_ROOT}}/roms/wiiu/roms" "{{EMU_ROOT}}/roms/wiiu/mlc01" "{{EMU_ROOT}}/tools"; do
        if [[ -d "$dir" ]]; then
            echo "==> exists, left alone: $dir"
        else
            mkdir -p "$dir"
            echo "==> created: $dir"
        fi
    done

# Let the sandboxed Cemu read the ROM directory, and confirm it is installed.
emulation-permissions:
    #!/usr/bin/bash
    set -euo pipefail

    if ! flatpak info "{{CEMU_ID}}" >/dev/null 2>&1; then
        echo "Cemu is not installed yet." >&2
        echo "It ships with this image via default-flatpaks; if it is missing," >&2
        echo "the first-boot flatpak install has not run or has failed. Check with:" >&2
        echo "  systemctl list-units --all | grep -i flatpak" >&2
        exit 1
    fi

    # A flatpak cannot see ~/Emulation without this - the ROM folder is outside
    # its sandbox, so without the override Cemu simply shows an empty game list.
    flatpak override --user --filesystem="{{EMU_ROOT}}" "{{CEMU_ID}}"
    echo "==> Cemu granted read/write access to {{EMU_ROOT}}"

    if flatpak info "{{SRM_ID}}" >/dev/null 2>&1; then
        flatpak override --user --filesystem="{{EMU_ROOT}}" "{{SRM_ID}}"
        echo "==> Steam ROM Manager granted access to {{EMU_ROOT}}"
    fi

# Print where Cemu keeps its configuration, keys and caches.
emulation-paths:
    @echo "Cemu is a flatpak, so its paths are NOT the native ones EmuDeck documents:"
    @echo ""
    @echo "  config + controller profiles"
    @echo "    ~/.var/app/{{CEMU_ID}}/config/Cemu/"
    @echo "  data, graphic packs, shader cache, keys.txt"
    @echo "    ~/.var/app/{{CEMU_ID}}/data/Cemu/"
    @echo "  your game dumps (outside the sandbox, access granted explicitly)"
    @echo "    {{EMU_ROOT}}/roms/wiiu/roms"
    @echo "  persistent game storage / saves"
    @echo "    {{EMU_ROOT}}/roms/wiiu/mlc01"
    @echo ""
    @echo "keys.txt goes in the data path above. Provide your own; none ship here."

# Performance checklist for the Radeon 780M. Deliberately not automated.
emulation-tune:
    @echo "Apply these in Cemu once (Options > General settings / Graphics):"
    @echo ""
    @echo "  Graphics API            Vulkan"
    @echo "  Graphics device         Radeon 780M"
    @echo "  VSync                   On  (HTPC on a TV - tearing is worse than a"
    @echo "                              frame of latency, and it caps the iGPU)"
    @echo "  Async shader compile    On  (this is the big one: without it you get"
    @echo "                              a stutter at every new shader)"
    @echo "  Accurate barriers       On  (leave default; off is a stability risk)"
    @echo "  Upscale/downscale       Bilinear, full sync at GX2DrawDone off"
    @echo ""
    @echo "Per-game, via Graphic Packs:"
    @echo "  - set resolution to 1920x1080; do NOT go above native TV resolution"
    @echo "  - demanding titles (e.g. Breath of the Wild) are steadier at a 40 FPS"
    @echo "    cap than chasing 60 and missing it"
    @echo ""
    @echo "Not written automatically on purpose: a malformed settings.xml stops"
    @echo "Cemu from starting, and overwriting an existing one would throw away"
    @echo "controller profiles you had already set up."

# Add Wii U games to Steam with artwork, via Steam ROM Manager.
emulation-steam:
    #!/usr/bin/bash
    set -euo pipefail

    if ! flatpak info "{{SRM_ID}}" >/dev/null 2>&1; then
        echo "Steam ROM Manager is not installed." >&2
        exit 1
    fi

    echo "Steam ROM Manager is a GUI and needs one pass in Desktop Mode."
    echo "There is no headless equivalent, so this cannot be fully automated."
    echo ""
    echo "  1. Close Steam completely first (SRM edits Steam's shortcuts file;"
    echo "     with Steam running your entries get overwritten on exit)."
    echo "  2. Pick the parser 'Nintendo WiiU - Cemu (.wua) - Native' or the"
    echo "     .rpx variant, matching your dump format."
    echo "  3. Point it at {{EMU_ROOT}}/roms/wiiu/roms"
    echo "  4. Test Parser, check the titles, then Parse and Save to Steam."
    echo ""
    echo "Do NOT enable Proton compatibility on Cemu or on the games it adds -"
    echo "this is a native Linux build and Proton breaks it."
    echo ""
    flatpak run "{{SRM_ID}}"
