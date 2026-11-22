#!/bin/sh
# The Gooswan regression battery: unit self-tests, the 8086
# corpus baseline, WSHWTest Test All, the framebuffer goldens and
# every WSTimingTest case across all 29 pages.
# Expects the corpus (scripts/fetch_corpus.sh) and the test ROMs
# (scripts/fetch_test_roms.sh) to be in place, and tools/sst built.
set -e
cd "$(dirname "$0")/.."
SST=./tools/sst
# Windows' C runtime ends printed lines with \r\n; strip the \r so the
# parsing below is the same on every platform. Keeps sst's exit status.
sst() { _out=$("$SST" "$@") || return; printf '%s\n' "$_out" | tr -d '\r'; }
for t in cpu_test ppu_test apu_test eeprom_test state_test serial_test; do
    out=$(sst $t)
    echo "$out"
    echo "$out" | grep -q ", 0 failed" || { echo "FAIL: $t" >&2; exit 1; }
done
./app/gooswan --self-test
./app/gooswan --link-self-test
./tools/audio_test
sh ./tests/cli_check.sh
total=$(sst tests/data/*.json | awk -F'[= ]' '/total=/{t+=$3; p+=$5} END {print p"/"t}')
echo "8086 corpus: $total"
[ "$total" = "634406/646000" ] || { echo "FAIL: corpus baseline moved ($total)" >&2; exit 1; }
testall=$(mktemp)
trap 'rm -f "$testall"' EXIT
sst ws tests/roms/WSHWTest.wsc m1 > "$testall" 2>&1
if grep -qi failed "$testall"; then echo "FAIL: WSHWTest Test All" >&2; exit 1; fi
echo "WSHWTest Test All: pass"
sh ./tests/fb_check.sh
pass=0
fail=0
for n in $(seq 0 28); do
    out=$(sst ws tests/roms/WSTimingTest.ws "pg$n")
    final=$(printf '%s\n' "$out" | awk '/^final screen/{buf=""; next} {buf=buf $0 "\n"} END{printf "%s", buf}')
    p=$(printf '%s' "$final" | grep -oE ':[.]+[0-9]+[.]+[0-9]+[.]+o[.]' | wc -l)
    f=$(printf '%s' "$final" | grep -oE ':[.]+[0-9]+[.]+[0-9]+[.]+x[.]' | wc -l)
    pass=$((pass + p))
    fail=$((fail + f))
done
echo "WSTimingTest harvest: $pass passed, $fail failed"
[ "$pass" = 407 ] && [ "$fail" = 0 ] || { echo "FAIL: expected all 407 timing cases to pass" >&2; exit 1; }
echo "all tests passed"
