#!/bin/zsh
# Evidence logger: runs a command, prints it, and saves the exact output
# with a header (time, machine, IP) so every result is traceable.
#
# Usage:  ev.sh <output-file.txt> '<command>'
# Example: ev.sh Extension_B_DNS_TTL/B1_ttl_30_seconds.txt 'dig @10.7.9.246 app.team1.test'
#
# Relative output paths are placed under evidence/.

set -u
out="$1"; shift
cmd="$*"
base="$(cd "$(dirname "$0")/.." && pwd)/evidence"
[[ "$out" = /* ]] || out="$base/$out"
mkdir -p "$(dirname "$out")"

{
  echo "=================================================================="
  echo "Time    : $(date '+%Y-%m-%d %H:%M:%S %Z')"
  echo "Machine : $(scutil --get ComputerName 2>/dev/null) ($(ipconfig getifaddr en0 2>/dev/null))"
  echo "Command : $cmd"
  echo "------------------------------------------------------------------"
  zsh -c "$cmd" 2>&1
  echo "[exit code: $?]"
  echo
} | tee -a "$out"
