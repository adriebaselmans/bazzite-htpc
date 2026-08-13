# HTPC setup for this image: Waydroid + SmartTube, Kodi + xstreamflex.
#
# These live here rather than in the image because none of it can be baked in:
# Waydroid downloads its Android system/vendor images at init time, and Steam's
# and Kodi's configuration lives in $HOME. Everything below is re-runnable, so
# after a rebase or a reinstall you just run `ujust setup-htpc` again.

# Android 13 (a13-tv), NOT a16-tv. Android 16 needs the `aidl6` servicemanager
# protocol, and the host's libgbinder (1.1.43 on Fedora 43) only implements
# aidl..aidl4 - so the container boots fine but the host can never resolve the
# `waydroidplatform` service, and every waydroid command retries forever.
# Nothing in waydroid.cfg fixes that; it needs a newer libgbinder. Do not bump
# this to a15/a16 without first checking `strings libgbinder.so.1 | grep Aidl`.
WAYDROID_OTA_SYSTEM := "https://waydroid-atv.github.io/ota/a13-tv/system"
WAYDROID_OTA_VENDOR := "https://waydroid-atv.github.io/ota/a13-tv/vendor"
XSTREAMFLEX_REPO := "https://github.com/adriebaselmans/xstreamflex"
SMARTTUBE_API := "https://api.github.com/repos/yuliskov/SmartTube/releases?per_page=30"

# Set up everything: Waydroid + SmartTube, Kodi + xstreamflex, Steam entry.
setup-htpc: htpc-waydroid htpc-smarttube htpc-xstreamflex htpc-steam-shortcut
    @echo ""
    @echo "HTPC setup done. Remaining manual steps:"
    @echo "  - pair your remote/controller:  ujust htpc-remote"
    @echo "  - verify 4K + GPU decoding:     radeontop  (while playing a 4K video)"

# Initialise Waydroid with the Android TV image (not the default phone image).
htpc-waydroid force="0":
    #!/usr/bin/bash
    set -euo pipefail

    if [[ -f /var/lib/waydroid/waydroid.cfg && "{{force}}" != "1" ]]; then
        echo "==> Waydroid already initialised; skipping."
        echo "    Re-run as 'ujust htpc-waydroid 1' to force a clean re-init."
    else
        # The Android TV build, not Bazzite's own `ujust setup-waydroid` which
        # uses the standard phone LineageOS image. This one also bundles ARM
        # translation, which SmartTube needs: it publishes no x86_64 APK.
        echo "==> Initialising Waydroid with the Android TV image..."
        sudo waydroid init -f \
            -c "{{WAYDROID_OTA_SYSTEM}}" \
            -v "{{WAYDROID_OTA_VENDOR}}" \
            -r lineage \
            -s GAPPS
    fi

    sudo systemctl enable --now waydroid-container.service
    echo "==> Waydroid container service enabled."

# Download and install the latest stable SmartTube (arm64) into Waydroid.
htpc-smarttube:
    #!/usr/bin/bash
    set -euo pipefail

    if [[ ! -f /var/lib/waydroid/waydroid.cfg ]]; then
        echo "Waydroid is not initialised yet - run 'ujust htpc-waydroid' first." >&2
        exit 1
    fi

    echo "==> Looking up the latest stable SmartTube release..."
    # Stable releases are tagged with a trailing 's' (e.g. 32.10s); the beta of
    # the same version carries the bare tag. Assets are named
    # SmartTube_stable_<version>_<arch>.apk - we want arm64-v8a, translated by
    # the ARM layer in the Android TV image.
    # Kept to grep/sed rather than a multi-line python heredoc: every line of a
    # just recipe must stay indented, and an unindented heredoc silently ends
    # the recipe body - which just then reports as a syntax error on the first
    # line of the embedded script.
    #
    # The API returns releases newest-first, and only stable builds carry
    # "_stable_" in their asset names, so the first match is the newest stable
    # arm64 APK.
    url="$(curl -fsSL "{{SMARTTUBE_API}}" \
        | grep -o '"browser_download_url": *"[^"]*_stable_[^"]*_arm64-v8a\.apk"' \
        | head -1 | sed 's/.*"\(https[^"]*\)"$/\1/')"

    if [[ -z "$url" ]]; then
        echo "Found no stable arm64-v8a SmartTube asset." >&2
        exit 1
    fi

    echo "==> Installing $(basename "$url")"
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    curl -fsSL -o "$tmp/smarttube.apk" "$url"

    # A running session is required before apps can be installed.
    if ! waydroid status 2>/dev/null | grep -qi 'session.*running'; then
        echo "==> Starting a Waydroid session..."
        waydroid session start &
        sleep 15
    fi
    waydroid app install "$tmp/smarttube.apk"
    echo "==> SmartTube installed."
    echo "    Start it from the Android TV launcher, not 'waydroid app launch' -"
    echo "    the back button does not work when launched directly."

# Build and install the xstreamflex add-on into the Kodi flatpak.
htpc-xstreamflex ref="main":
    #!/usr/bin/bash
    set -euo pipefail

    dest="$HOME/.var/app/tv.kodi.Kodi/data/addons"
    if [[ ! -d "$HOME/.var/app/tv.kodi.Kodi" ]]; then
        echo "Kodi's flatpak data dir does not exist yet." >&2
        echo "Start Kodi once so it creates it, then re-run this." >&2
        exit 1
    fi

    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    echo "==> Fetching xstreamflex ({{ref}})..."
    git clone --depth 1 --branch "{{ref}}" "{{XSTREAMFLEX_REPO}}" "$tmp/src"

    # package.py refuses to emit a ZIP with a shape Kodi would reject, so a
    # successful build here means it will install cleanly.
    echo "==> Building the add-on ZIP..."
    python3 "$tmp/src/tools/package.py"

    zip="$(find "$tmp/src/dist" -name '*.zip' | head -1)"
    if [[ -z "$zip" ]]; then
        echo "package.py produced no ZIP." >&2
        exit 1
    fi

    echo "==> Installing into $dest"
    mkdir -p "$dest"
    rm -rf "$dest/plugin.video.xstreamflex"
    unzip -q "$zip" -d "$dest"
    echo "==> Done. Kodi will pick it up on next start."
    echo "    script.module.requests installs itself from Kodi's own repo."

# Add Kodi and Waydroid to Steam so both are reachable from Game Mode.
htpc-steam-shortcut:
    #!/usr/bin/bash
    set -euo pipefail

    # Steam stores non-Steam shortcuts in a *binary* shortcuts.vdf. Editing that
    # from a script is genuinely fiddly and easy to corrupt, so this defers to
    # steamtinkerlaunch when it is present and otherwise tells you to do the two
    # manual steps rather than pretending it worked.
    if command -v steamtinkerlaunch >/dev/null 2>&1; then
        echo "==> Adding Kodi via steamtinkerlaunch..."
        steamtinkerlaunch addnonsteamgame \
            --appname="Kodi" \
            --exepath="/usr/bin/flatpak" \
            --launchoptions="run tv.kodi.Kodi" \
            || echo "    steamtinkerlaunch failed - add it by hand (see below)."

        # /usr/bin/waydroid-launcher is Bazzite's own wrapper: it runs Waydroid
        # inside cage, which nests under gamescope, and its pkexec calls are
        # already allowed for the wheel group so nothing prompts in Game Mode.
        # With no arguments it runs show-full-ui, so this lands on the Android
        # TV home screen; open SmartTube from there. It does accept arguments
        # (app launch org.smarttube.stable) for a one-tap tile, but SmartTube
        # started that way has a broken back button - hence the plain launcher.
        echo "==> Adding Waydroid via steamtinkerlaunch..."
        steamtinkerlaunch addnonsteamgame \
            --appname="Waydroid" \
            --exepath="/usr/bin/waydroid-launcher" \
            || echo "    steamtinkerlaunch failed - add it by hand (see below)."
    else
        echo "==> steamtinkerlaunch not found; add these by hand (one-time):"
        echo "    Desktop mode > Steam > Games > Add a Non-Steam Game > Browse"
        echo "    Kodi     - Target: /usr/bin/flatpak            Options: run tv.kodi.Kodi"
        echo "    Waydroid - Target: /usr/bin/waydroid-launcher"
        echo "    Neither appears in Game Mode until you do this."
    fi

# Pair a Bluetooth remote or controller and point at the Kodi keymap.
htpc-remote:
    #!/usr/bin/bash
    set -euo pipefail

    echo "Put the remote/controller in pairing mode, then in the bluetoothctl"
    echo "prompt that follows run:"
    echo ""
    echo "    scan on          # wait for your device to appear"
    echo "    pair <MAC>"
    echo "    trust <MAC>      # do not skip: without trust it will not reconnect"
    echo "    connect <MAC>"
    echo "    quit"
    echo ""
    echo "The NVIDIA Shield remote shows up as a keyboard HID (0955:7217)."
    echo "Known issue: its pairing can be lost across reboots, and the community"
    echo "fix does not solve that. If that bites, a Flirc USB (IR) or a"
    echo "Pulse-Eight USB-CEC adapter is the more reliable route - this machine"
    echo "has no HDMI-CEC of its own, unlike the Shield."
    echo ""
    echo "Remap keys afterwards in Kodi via the Keymap Editor add-on."
    echo ""
    bluetoothctl
