#!/bin/bash
# Turns the Mi Box into the same Simple Home setup as the Hisense TV:
# installs the launcher and BBC Radio (built in ../hisense), disables the stock
# launchers and everything in bloat.txt, and speeds up animations.
# It also turns on parental TV time controls, with an HTTP API on the box (port 8080).
# Everything it changes is undone by rollback.sh.
set -euo pipefail
cd "$(dirname "$0")"

BOX="${BOX:-192.168.7.86:5555}"
# Name shown next to the clock on this box.
TITLE="${TITLE:-Ariya TV}"
ME=th.co.dits.simplehome
APKS=../hisense
# Bearer token for the parental API, created on the first deploy and kept here.
TOKEN_FILE=parental-token.txt
A="adb -s $BOX"
# A screensaver that doesn't depend on Backdrop, which bloat.txt disables.
SCREENSAVER=com.android.dreams.basic/.Colors

adb connect "$BOX" >/dev/null
$A wait-for-device

# Snapshot the box before touching anything (only the first time).
if [ ! -f box-before.txt ]; then
    {
        echo "sdk=$($A shell getprop ro.build.version.sdk)"
        echo "model=$($A shell getprop ro.product.model)"
        echo "home=$($A shell cmd package resolve-activity --brief -c android.intent.category.HOME -a android.intent.action.MAIN | tail -1)"
        for k in window_animation_scale transition_animation_scale animator_duration_scale; do
            echo "$k=$($A shell settings get global $k)"
        done
        echo "screensaver=$($A shell settings get secure screensaver_components)"
    } > box-before.txt
    $A shell pm list packages -e | sort > box-packages-before.txt
fi
cat box-before.txt

$A install -r "$APKS/simplehome.apk"
$A install -r "$APKS/bbcradio/bbcradio.apk"

# Only record packages this script disabled, so rollback leaves anything else alone.
disable_into() {
    local list=$1 pkg=$2
    [ -z "$pkg" ] || [ "$pkg" = "$ME" ] && return
    grep -qx "$pkg" "$list" 2>/dev/null && return
    grep -qx "package:$pkg" box-packages-before.txt || return 0
    if $A shell pm disable-user --user 0 "$pkg" </dev/null >/dev/null; then echo "$pkg" >> "$list"; else echo "could not disable $pkg"; fi
}

# Stock launchers that would otherwise grab the HOME button.
STOCK=$(grep '^home=' box-before.txt | cut -d= -f2 | cut -d/ -f1)
[ -f disabled-launchers.txt ] || : > disabled-launchers.txt
for pkg in "$STOCK" com.google.android.tvlauncher com.google.android.leanbacklauncher com.google.android.apps.tv.launcherx; do
    disable_into disabled-launchers.txt "$pkg"
done

$A shell settings put secure screensaver_components "$SCREENSAVER"
[ -f disabled-apps.txt ] || : > disabled-apps.txt
grep -vE '^\s*(#|$)' bloat.txt | while read -r pkg; do
    disable_into disabled-apps.txt "$pkg"
done

$A shell cmd package set-home-activity "$ME/.HomeActivity" || true

for k in window_animation_scale transition_animation_scale animator_duration_scale; do
    $A shell settings put global $k 0.5
done

# Parental mode: watch which app is in front, show the time-left banner over other apps,
# keep the service out of Doze, and keep the clock automatic so time limits hold.
if [ ! -s "$TOKEN_FILE" ]; then
    (umask 077; head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$TOKEN_FILE")
fi
$A shell appops set $ME GET_USAGE_STATS allow
$A shell appops set $ME SYSTEM_ALERT_WINDOW allow
$A shell dumpsys deviceidle whitelist +$ME >/dev/null
$A shell settings put global auto_time 1

# No -W: while the TV is locked the lock screen covers the home screen at once, and -W can wait forever.
$A shell am start -n "$ME/.HomeActivity" --es title "\"$TITLE\"" --es api_token "$(cat "$TOKEN_FILE")"
echo "Disabled launchers: $(tr '\n' ' ' < disabled-launchers.txt)"
echo "Disabled apps: $(tr '\n' ' ' < disabled-apps.txt)"
IP=${BOX%%:*}
echo "TV time page: http://$IP:8080/   (token in $(pwd)/$TOKEN_FILE)"
echo "API example:  curl -H \"Authorization: Bearer \$(cat $TOKEN_FILE)\" http://$IP:8080/api/status"
