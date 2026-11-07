#!/bin/bash
# Puts the Mi Box back the way deploy.sh found it.
set -uo pipefail
cd "$(dirname "$0")"

BOX="${BOX:-192.168.7.86:5555}"
A="adb -s $BOX"

adb connect "$BOX" >/dev/null
$A wait-for-device

for f in disabled-launchers.txt disabled-apps.txt; do
    [ -f "$f" ] || continue
    while read -r pkg; do
        [ -n "$pkg" ] && $A shell pm enable "$pkg" </dev/null
    done < "$f"
    rm -f "$f"
done

for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    v=$(grep "^$k=" box-before.txt 2>/dev/null | cut -d= -f2)
    if [ -z "$v" ] || [ "$v" = "null" ]; then
        $A shell settings delete global $k
    else
        $A shell settings put global $k "$v"
    fi
done

ss=$(grep '^screensaver=' box-before.txt 2>/dev/null | cut -d= -f2)
[ -n "$ss" ] && [ "$ss" != "null" ] && $A shell settings put secure screensaver_components "$ss"

$A shell dumpsys deviceidle whitelist -th.co.dits.simplehome >/dev/null
$A uninstall th.co.dits.simplehome
$A uninstall th.co.dits.bbcradio
$A shell input keyevent KEYCODE_HOME
echo "Rolled back."
