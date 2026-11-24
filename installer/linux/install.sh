#!/usr/bin/env bash
# Anarva installer for Linux.
#
# Copies Anarva/stable from this folder into <BAR data>/AI/Skirmish/Anarva/stable/ and adds the
# libSkirmishAI.so from the newest installed engine's BARb (Anarva runs on BARb's C++ core and does not
# ship its own copy, so the library always matches the engine your game uses).
#
#   ./install.sh                                   find the BAR data folder and install
#   ./install.sh "/path/to/Beyond All Reason"      install into that data folder
#   ./install.sh --uninstall                       remove Anarva again
#   ./install.sh --dry-run                         print what would be done, change nothing
#
# Run it again after BAR updates its engine, to pick up the new libSkirmishAI.so.
set -euo pipefail

AI_NAME="Anarva"
LIB_NAME="libSkirmishAI.so"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

BAR_DATA=""
UNINSTALL=0
DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --uninstall) UNINSTALL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "ERROR: unknown option '$arg' (use --uninstall, --dry-run or a data folder path)" >&2; exit 1 ;;
        *) BAR_DATA="$arg" ;;
    esac
done

die() { echo >&2; echo "ERROR: $*" >&2; exit 1; }
step() { if [ "$DRY_RUN" = 1 ]; then echo "[dry run] would $*"; else echo "$*"; fi; }

is_bar_data() {
    local dir="$1"
    [ -n "$dir" ] && [ -d "$dir/engine" ] || return 1
    compgen -G "$dir/engine/recoil_*/" > /dev/null
}

has_tty() { { : < /dev/tty; } 2> /dev/null; }

ask() {
    # read from the terminal even when stdin is a pipe; fail clearly when there is none
    local prompt="$1" reply
    has_tty || die "no terminal to ask on: $prompt (pass the BAR data folder as an argument)"
    read -r -p "$prompt" reply < /dev/tty || reply=""
    printf '%s' "$reply"
}

ask_for_path() {
    echo "$1" >&2
    echo "The BAR data folder is the one that contains the 'engine', 'maps' and 'games' folders," >&2
    echo "for example \"$HOME/.local/state/Beyond All Reason\"" >&2
    local answer
    while true; do
        answer="$(ask "Path to the BAR data folder (empty to cancel): ")" || exit 1
        [ -n "$answer" ] || die "cancelled: no BAR data folder given"
        if is_bar_data "$answer"; then (cd "$answer" && pwd); return; fi
        echo "'$answer' has no engine/recoil_* folder, so it is not a BAR data folder. Try again." >&2
    done
}

select_bar_data() {
    if [ -n "$BAR_DATA" ]; then
        is_bar_data "$BAR_DATA" || die "'$BAR_DATA' is not a BAR data folder: it has no engine/recoil_* folder"
        (cd "$BAR_DATA" && pwd)
        return
    fi
    local candidates=(
        "$HOME/.local/state/Beyond All Reason"
        "$HOME/.local/share/Beyond All Reason"
        "$HOME/Beyond-All-Reason/data"
    )
    if [ -n "${XDG_STATE_HOME:-}" ]; then candidates+=("$XDG_STATE_HOME/Beyond All Reason"); fi
    local found=() c full f dup
    for c in "${candidates[@]}"; do
        is_bar_data "$c" || continue
        full="$(cd "$c" && pwd -P)"
        dup=0
        for f in "${found[@]+"${found[@]}"}"; do if [ "$f" = "$full" ]; then dup=1; fi; done
        if [ "$dup" = 0 ]; then found+=("$full"); fi
    done
    if [ "${#found[@]}" -eq 1 ]; then
        echo "Found the BAR data folder: ${found[0]}" >&2
        printf '%s\n' "${found[0]}"
        return
    fi
    if [ "${#found[@]}" -eq 0 ]; then
        ask_for_path "Could not find the Beyond All Reason data folder in the usual places."
        return
    fi
    echo "Found several BAR data folders:" >&2
    local i answer
    for i in "${!found[@]}"; do echo "  $((i + 1))) ${found[$i]}" >&2; done
    while true; do
        answer="$(ask "Number of the one to use, or a full path: ")" || exit 1
        if [[ "$answer" =~ ^[0-9]+$ ]] && [ "$answer" -ge 1 ] && [ "$answer" -le "${#found[@]}" ]; then
            printf '%s\n' "${found[$((answer - 1))]}"
            return
        fi
        if [ -n "$answer" ] && is_bar_data "$answer"; then (cd "$answer" && pwd); return; fi
        echo "Not a number from the list or a BAR data folder: '$answer'" >&2
    done
}

find_engine() {
    # newest engine (version sort) whose BARb has the library
    local data="$1" e newest=""
    while IFS= read -r e; do
        if [ -f "$data/engine/$e/AI/Skirmish/BARb/stable/$LIB_NAME" ]; then newest="$e"; fi
    done < <(cd "$data/engine" && for d in recoil_*/; do printf '%s\n' "${d%/}"; done | sort -V)
    [ -n "$newest" ] || die "no engine under $data/engine has AI/Skirmish/BARb/stable/$LIB_NAME. Start BAR once so it downloads an engine, then run this again."
    printf '%s\n' "$newest"
}

lobby_help() {
    local data="$1" devmode="$1/devmode.txt" answer
    echo
    echo "To see Anarva in the lobby (it lists only its built-in AIs by default):"
    echo "  1. create an empty file $devmode"
    echo "  2. restart the BAR lobby"
    echo "  3. Settings > Developer > untick 'simple AI list'"
    echo "Anarva then appears as 'Anarva stable' in the Add AI list."
    echo
    if [ -e "$devmode" ]; then echo "devmode.txt already exists, so step 1 is done."; return; fi
    if [ "$DRY_RUN" = 1 ]; then echo "[dry run] would offer to create $devmode (y/n)"; return; fi
    if ! has_tty; then echo "No terminal to ask on: do step 1 yourself."; return; fi
    answer="$(ask "Create devmode.txt now? (y/n) ")"
    case "${answer,,}" in
        y|yes) : > "$devmode"; echo "Created $devmode" ;;
        *) echo "devmode.txt not created. Do step 1 yourself if Anarva does not show up." ;;
    esac
}

install_ai() {
    local data="$1"
    local src="$HERE/$AI_NAME/stable"
    [ -f "$src/AIInfo.lua" ] || die "this installer must sit next to the '$AI_NAME' folder from the release archive (missing $src/AIInfo.lua). Extract the whole archive first."
    # Releases bundle Anarva's own core (BARb's CircuitAI + the bridge Anarva's scripts need). Without it,
    # fall back to BARb's library from the newest engine (older Anarva scripts only).
    local bundled=0 engine="" lib="$src/$LIB_NAME"
    if [ -f "$lib" ]; then bundled=1; else engine="$(find_engine "$data")"; lib="$data/engine/$engine/AI/Skirmish/BARb/stable/$LIB_NAME"; fi
    local ai_root="$data/AI/Skirmish/$AI_NAME"
    local dst="$ai_root/stable" tmp="$ai_root/stable.installing"
    local count; count="$(find "$src" -type f | wc -l | tr -d ' ')"

    echo "BAR data folder: $data"
    if [ "$bundled" = 1 ]; then echo "Using Anarva's bundled core: $LIB_NAME"; else echo "Newest engine with BARb: $engine"; fi
    if [ -e "$tmp" ]; then step "remove leftover $tmp"; [ "$DRY_RUN" = 1 ] || rm -rf -- "$tmp"; fi
    step "copy $count files from $src to $tmp"
    [ "$bundled" = 1 ] || step "copy $lib to $tmp/$LIB_NAME"
    if [ "$DRY_RUN" = 0 ]; then
        mkdir -p "$tmp"
        cp -R "$src/." "$tmp/"
        local expect="$count"
        if [ "$bundled" = 0 ]; then cp "$lib" "$tmp/$LIB_NAME"; expect=$((count + 1)); fi
        local copied; copied="$(find "$tmp" -type f | wc -l | tr -d ' ')"
        [ "$copied" -eq "$expect" ] || die "copy incomplete: expected $expect files in $tmp, found $copied"
    fi
    if [ -e "$dst" ]; then step "remove the previous install $dst"; [ "$DRY_RUN" = 1 ] || rm -rf -- "$dst"; fi
    step "rename $tmp to $dst"
    [ "$DRY_RUN" = 1 ] || mv -- "$tmp" "$dst"
    echo
    if [ "$DRY_RUN" = 1 ]; then
        echo "Dry run finished: nothing was changed."
    else
        if [ "$bundled" = 1 ]; then echo "Installed $AI_NAME into $dst ($count files, bundled core)."
        else echo "Installed $AI_NAME into $dst ($count files + $LIB_NAME from $engine)."; echo "Run this installer again after BAR updates its engine."; fi
    fi
    lobby_help "$data"
}

uninstall_ai() {
    local data="$1" ai_root="$1/AI/Skirmish/$AI_NAME"
    if [ ! -e "$ai_root" ]; then echo "$AI_NAME is not installed in $data (no $ai_root). Nothing to do."; return; fi
    step "remove $ai_root"
    if [ "$DRY_RUN" = 0 ]; then rm -rf -- "$ai_root"; echo "Uninstalled $AI_NAME."; fi
    if [ -e "$data/devmode.txt" ]; then
        echo "$data/devmode.txt was left in place; delete it yourself if no other AI or tool needs developer mode."
    fi
}

if [ "$DRY_RUN" = 1 ]; then echo "Dry run: nothing will be changed."; fi
DATA="$(select_bar_data)"
if [ "$UNINSTALL" = 1 ]; then uninstall_ai "$DATA"; else install_ai "$DATA"; fi
