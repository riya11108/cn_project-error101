#!/bin/zsh
# Real screenshot evidence: opens a fresh Terminal.app window, runs the command live in it,
# then captures ONLY that window (no desktop / other apps) and closes it.
#
# Usage:  shot.sh <output.png> '<command>' [label]
#   Relative output paths go under evidence/.
# Example: shot.sh Extension_A_Backup_DNS/A3_backup_dns_resolution.png 'dig @10.7.31.224 app.team1.test'

set -u
out="$1"; cmd="$2"; label="${3:-}"
EVROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ "$out" = /* ]] || out="$EVROOT/evidence/$out"
mkdir -p "$(dirname "$out")"

work=$(mktemp -d /tmp/cnshot.XXXXXX)
runner="$work/run.zsh"; done_flag="$work/done"
cat > "$runner" <<EOF
clear
printf '\e[1;36m%s\e[0m\n' "MAC 1 — Manpreet  |  \$(scutil --get ComputerName) (\$(ipconfig getifaddr en0))  |  \$(date '+%Y-%m-%d %H:%M:%S %Z')"
[[ -n "$label" ]] && printf '\e[1;33m%s\e[0m\n' "$label"
printf '\e[1;32m%s\e[0m %s\n' "\$(whoami)@\$(hostname -s) %" ${(q)cmd}
cd "$EVROOT"
$cmd
echo
touch "$done_flag"
EOF

wid=$(osascript <<EOF
tell application "Terminal"
  activate
  set t to do script "clear; zsh '$runner'"
  set w to (first window whose tabs contains t)
  set bounds of w to {40, 40, 1100, 760}
  set index of w to 1
  return id of w
end tell
EOF
)
for i in {1..120}; do [[ -f "$done_flag" ]] && break; sleep 0.5; done
sleep 0.8
osascript -e "tell application \"Terminal\" to activate" -e "tell application \"Terminal\" to set index of (first window whose id is $wid) to 1" >/dev/null 2>&1
sleep 0.4
screencapture -x -R 40,40,1060,720 "$out"
python3 "$EVROOT/scripts/trim.py" "$out" 2>/dev/null
osascript -e "tell application \"Terminal\" to close (every window whose id is $wid)" >/dev/null 2>&1
rm -rf "$work"
if [[ -s "$out" ]]; then echo "saved: $out"; else echo "FAILED: $out"; exit 1; fi
