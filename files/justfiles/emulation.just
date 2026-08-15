# Nintendo Switch emulation (Eden) via EmuDeck, alongside the existing HTPC setup.
#
# EmuDeck is installed through bazzite-portal, which ships with Bazzite itself -
# no custom installer here. EmuDeck then owns the whole emulation stack: it
# installs Eden, creates ~/Emulation, and bundles its own Steam ROM Manager.
#
# Because it owns that stack, this image deliberately does NOT also ship Eden or
# Steam ROM Manager as flatpaks. Installing both gives you two Edens and two
# SRMs with separate configs, which is how duplicate Steam shortcuts happen.
# (Eden ships as AppImage only from git.eden-emu.dev, not as a Flatpak.)
#
# Legal note: Switch emulation sits on much shakier legal ground than Wii U.
# Nintendo sued and shut down Yuzu (2024, $2.4M settlement) and Ryujinx (Oct
# 2024) directly after contacting devs; successor forks faced ongoing DMCA
# takedowns into 2026 (e.g. Suyu ceased development Feb 2025). Eden and a
# Ryujinx-continuation fork called "Ryubing" (git.ryujinx.app) are current
# survivors as of August 2026, but this could change again.

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

    if ! command -v yafti_gtk.py >/dev/null 2>&1; then
        echo "yafti_gtk.py is not available on this image." >&2
        echo "It ships with Bazzite itself (package bazzite-portal), so this is" >&2
        echo "unexpected - check that you are running the bazzite-deck base" >&2
        echo "rather than something else." >&2
        exit 1
    fi

    echo "Opening Bazzite Portal. Pick EmuDeck, then in EmuDeck's own setup:"
    echo "  - choose Custom install if you want to pick emulators individually"
    echo "  - select 'Linux PC' (not 'Steam Deck' - this is a mini-PC)"
    echo "  - select 'High' integration (Steam ROM Manager, not EmulationStation)"
    echo "  - enable Eden (or Ryubing as a fallback)"
    echo "  - point storage at your preferred drive (default is fine)"
    echo ""
    echo "Note: EmuDeck 2.5.0's Eden auto-install is broken (upstream bug #1568,"
    echo "planned for 3.x). You will need to download and install Eden manually."
    echo "After EmuDeck finishes: run 'ujust emulation-paths' for instructions."
    echo ""
    echo "If EmuDeck adds an EmulationStationDE Steam shortcut (it may, but won't"
    echo "install ES-DE itself), delete it from Steam - not needed, use Steam tiles."
    echo ""
    echo "Afterwards:"
    echo "  ujust emulation-paths   where everything lives + manual Eden install"
    echo "  ujust emulation-tune    performance settings for the 780M"
    echo "  ujust emulation-steam   getting games into Steam"
    echo ""
    # The desktop entry (Name=Bazzite Portal) runs exactly this - the package is
    # called bazzite-portal, but that is not the name of anything it installs.
    yafti_gtk.py /usr/share/yafti/yafti.yml

# Print where to install Eden and where EmuDeck keeps ROMs, config, keys and saves.
emulation-paths:
    @echo "Manual Eden install (required - EmuDeck 2.5.0 auto-install is broken):"
    @echo "  1. Download the amd64-clang-pgo build from:"
    @echo "     https://git.eden-emu.dev/eden-emu/eden/releases"
    @echo "     (not -steamdeck or -rog-ally builds; clang-pgo is ~10-30% faster)"
    @echo "  2. Place it in: ~/Applications/"
    @echo "  3. Make it executable: chmod +x ~/Applications/Eden-Linux-*-amd64-clang-pgo.AppImage"
    @echo ""
    @echo "Once placed there, EmuDeck's own Steam ROM Manager parser will find it."
    @echo ""
    @echo "Eden paths (native Linux, not in ~/Emulation):"
    @echo "  ROM files (switch)       {{EMU_ROOT}}/roms/switch/"
    @echo "                            (extensions: .kip .nca .nro .nso .nsp .xci)"
    @echo "  config                   ~/.config/eden/"
    @echo "  keys.txt / title.keys     ~/.local/share/eden/keys/"
    @echo "  firmware/nand            ~/.local/share/eden/nand/"
    @echo "  save data                ~/.local/share/eden/nand/user/save"
    @echo "  Eden executable          ~/Applications/"
    @echo ""
    @echo "WARNING: ~/Emulation/bios/eden/ exists (EmuDeck creates it) but Eden"
    @echo "does NOT read from it. Keys and firmware must go in ~/.local/share/eden/"
    @echo "as shown above, or Eden will not find them. Confirmed by testing."
    @echo ""
    @echo "Keys and firmware must be dumped from your own real Switch console."
    @echo "Look for a firmware/system-files install option in Eden's own settings"
    @echo "to import them - firmware cannot simply be copied into a folder."

# Performance tuning for Eden on the Radeon 780M.
emulation-tune:
    @echo "Eden is configured through its own settings menu once running."
    @echo "Graphics options and per-game tuning are available there."
    @echo ""
    @echo "No FPS benchmarks exist yet for Eden on the Radeon 780M; performance"
    @echo "will depend on the specific game and your settings choices."
    @echo "Test with your preferred titles and adjust resolution / graphics"
    @echo "options as needed to balance visual quality and frame rate."

# How to get Switch games into Steam with artwork.
emulation-steam:
    @echo "Use the Steam ROM Manager that EmuDeck installed - not a separate one."
    @echo "Launch it from the EmuDeck app (Tools > Steam ROM Manager)."
    @echo ""
    @echo "  1. Close Steam completely first. SRM edits Steam's shortcuts file;"
    @echo "     with Steam running, your new entries are discarded on exit."
    @echo "  2. Enable ONLY 'Nintendo Switch - Eden' (Citron and Ryujinx are also"
    @echo "     pre-enabled by EmuDeck and scan the same folder - leaving them on"
    @echo "     adds every game as three duplicate Steam tiles). Check with:"
    @echo "     ~/Emulation/tools/Steam-ROM-Manager.AppImage list"
    @echo "     and disable the other two by ID if needed:"
    @echo "     ~/Emulation/tools/Steam-ROM-Manager.AppImage disable <id>"
    @echo "  3. Parser scans ~/Emulation/roms/switch/ for .kip/.nca/.nro/.nso/.nsp/.xci"
    @echo "     - each game as its own file, not a same-named folder wrapping it."
    @echo "  4. Test Parser, check the titles and artwork, then Parse + Save."
    @echo "  5. Back in Game Mode the games appear as normal Steam entries."
    @echo ""
    @echo "Never enable Proton compatibility on Eden or on the games SRM adds:"
    @echo "this is a native Linux build and Proton breaks it."
    @echo ""
    @echo "If a parser is enabled here but games still don't appear in Steam,"
    @echo "fix BOTH userConfigurations.json files, always, at the same time:"
    @echo "  ~/.config/EmuDeck/backend/configs/steam-rom-manager/userData/...  (template)"
    @echo "  ~/.config/steam-rom-manager/userData/...                          (the real one SRM reads)"
    @echo "Opening Steam ROM Manager through EmuDeck's own menu runs an rsync"
    @echo "(SRM_addExtraParsers in emuDeckSRM.sh) that copies the template over"
    @echo "the real file - fixing only the real one gets silently undone next"
    @echo "time you launch SRM via EmuDeck rather than the AppImage directly."
    @echo "Both can ship with a broken executor path for every emulator entry -"
    @echo "either /run/media/mmcblk0p1/... (a Steam Deck SD-card path) or"
    @echo "~/Emulation/tools/launchers/<emu>.sh (does not exist). Fix both"
    @echo "files' paths to point at ~/.config/EmuDeck/backend/tools/launchers/,"
    @echo "where the actual launcher scripts live."
    @echo ""
    @echo "After fixing shortcuts.vdf (by hand or via SRM), fully restart Steam -"
    @echo "it reads that file once at startup and won't notice edits otherwise."
    @echo ""
    @echo "Ryubing (a Ryujinx successor fork) also auto-installed if selected."
    @echo "It is unused but works as a fallback if Eden ever breaks."
