#!/usr/bin/env bash
# Runs audit-android-adb.sh against a fake adb that logs every call and
# checks that only read-only device commands are issued.
set -Eeuo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

cat > "$tmp/adb" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$ADB_LOG"
if [[ "$1" == devices ]]; then printf 'List of devices attached\nFAKESERIAL123\tdevice\n'; exit 0; fi
shift 3  # -s SERIAL shell
case "$*" in
    'getprop ro.product.model') echo 'Pixel 10 Pro XL' ;;
    'getprop ro.product.manufacturer') echo 'Google' ;;
    'getprop ro.build.version.release') echo '17' ;;
    'getprop ro.build.version.sdk') echo '37' ;;
    'getprop ro.build.version.security_patch') echo '2020-01-05' ;;
    'getprop ro.boot.verifiedbootstate') echo 'orange' ;;
    'getprop ro.boot.flash.locked') echo '0' ;;
    'getprop ro.build.tags') echo 'release-keys' ;;
    'getprop ro.debuggable') echo '0' ;;
    'getprop ro.crypto.state') echo 'encrypted' ;;
    'getprop ro.crypto.type') echo 'file' ;;
    'dumpsys lock_settings') echo '  CredentialType: PIN' ;;
    'settings get global adb_enabled') echo '1' ;;
    'settings get secure enabled_accessibility_services') echo 'com.spy.app/com.spy.app.Svc:com.google.android.marvin.talkback/.TalkBackService' ;;
    'settings get secure enabled_notification_listeners') echo 'com.google.android.gms/.Listener' ;;
    'cmd appops query-op --user 0 REQUEST_INSTALL_PACKAGES allow') echo 'com.termux' ;;
    'dumpsys device_policy') echo '    admin=ComponentInfo{com.spy.app/com.spy.app.Admin}' ;;
    'pm list packages -3 -i') printf 'package:com.termux  installer=null\npackage:com.whatsapp  installer=com.android.vending\n' ;;
    'pm list users') echo '	UserInfo{0:Owner:c13} running' ;;
    'ip -6 addr show scope global') echo '    inet6 2001:db8:1:2:1111:2222:3333:4444/64 scope global dynamic' ;;
    'netstat -tln') printf 'tcp6 0 0 :::11434 :::* LISTEN\ntcp 0 0 127.0.0.1:5037 0.0.0.0:* LISTEN\n' ;;
    'settings get '*) echo 'null' ;;
    *) ;;
esac
FAKE
chmod +x "$tmp/adb"

out=$(cd "$tmp" && ADB_LOG="$tmp/calls.log" PATH="$tmp:$PATH" "$repo_dir/audit-android-adb.sh" --output "$tmp/report.md" 2>&1)

# Every device command must be a read.
if grep -vE '^(devices|-s FAKESERIAL123 shell (getprop|settings get|dumpsys|pm list|cmd appops query-op|netstat -tln|ip -6 addr show|command -v su))' "$tmp/calls.log"; then
    echo "FAIL: non read-only adb call issued" >&2
    exit 1
fi
grep -q 'Parche de seguridad 2020-01-05' <<<"$out"
grep -q 'CRÍTICO\] Parche' <<<"$out"
grep -q 'Verified Boot: orange' <<<"$out"
grep -q 'com.spy.app' <<<"$out"
grep -q 'Administrador de dispositivo: com.spy.app' <<<"$out"
grep -q 'Puerto 11434 escucha en todas las interfaces con IPv6 global' <<<"$out"
grep -q 'com.termux (instalador: desconocido)' <<<"$out"
grep -q 'Depuración USB activa' <<<"$out"
if grep -q 'FAKESERIAL123' "$tmp/report.md"; then echo "FAIL: serial not redacted" >&2; exit 1; fi
[[ $(stat -c '%a' "$tmp/report.md") == 600 ]] || { echo "FAIL: report is not 600" >&2; exit 1; }

echo "PASS: Android ADB audit is read-only, detects risks and redacts the serial"
