#!/bin/sh
#
# Read-only verification for the strict LG lockout bundle.
#
# Unlike the original forum verifier, this checks the exact custom mount
# source, accepts model-specific option keys that are absent, and checks
# numeric connections only against known numeric LG endpoints.

set -u

EXPECTED_HOSTS='
snu.lge.com
su.lge.com
su-ssl.lge.com
nsu.lge.com
snu-dev.lge.com
su-dev.lge.com
nextlgsdp.com
ibs.nextlgsdp.com
ibsstat.nextlgsdp.com
rdx2.nextlgsdp.com
lgtvcommon.com
netflixvoice.lgtvcommon.com
nudge.lgtvcommon.com
homeprv.lgtvcommon.com
wiseconfig.lgtvcommon.com
pnv.lgtvcommon.com
recommend.lgtvcommon.com
cdpsvc.lgtvcommon.com
cpauth.lgtvcommon.com
cdpbeacon.lgtvcommon.com
rdl.lgtvcommon.com
wiseresource.lgtvcommon.com
qcardservice.lgtvcommon.com
qt2-kic.lab.lgtvcommon.com
lggalleryplus.com
tv.wiselg.com
lgsmartad.com
info.lgsmartad.com
lgtviot.com
api.lgtviot.com
commonpush.lgtviot.com
sports.lgtviot.com
ocp.lgtviot.com
push.lgtviot.com
buddy.lgtviot.com
lgthinq.com
common.lgthinq.com
connect-client.lgthinq.com
ngfts.lge.com
qt2-ngfts.lge.com
kic-ngfts.lge.com
kic-qt2-ngfts.lge.com
lgsmartweb.com
lgvoice.com
lgtvsdp.com
lgappstv.com
lgshopsvc.lgappstv.com
'

EULA_FILE=/var/luna/preferences/eula
OPTION_FILE=/var/luna/preferences/option
GENERAL_FILE=/var/luna/preferences/general
ACR_DIR=/mnt/lg/cmn_data/acr/data
UPDATE_BASE=/mnt/lg/cmn_data/var/palm/data/com.webos.appInstallService

PASS=0
FAIL=0

ok() {
    PASS=$((PASS + 1))
    echo "  [PASS] $*"
}

bad() {
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $*"
}

info() {
    echo "  [INFO] $*"
}

section() {
    echo
    echo "== $* =="
}

section "Startup integration"
for script in \
    /var/lib/webosbrew/init.d/10-block-lg-telemetry \
    /var/lib/webosbrew/init.d/20-block-lg-ips \
    /var/lib/webosbrew/init.d/30-enforce-lg-privacy
do
    if [ -x "$script" ]; then
        ok "$(basename "$script") is executable"
    else
        bad "$(basename "$script") is missing or not executable"
    fi
done

if [ -e /var/luna/preferences/webosbrew_failsafe ]; then
    bad "Homebrew failsafe flag is active"
else
    ok "Homebrew failsafe flag is absent"
fi

section "Strict hosts block"
missing_hosts=""
for host in $EXPECTED_HOSTS; do
    if ! grep -Fqx "0.0.0.0 $host" /etc/hosts; then
        missing_hosts="$missing_hosts $host"
    fi
done

if [ -z "$missing_hosts" ]; then
    ok "all 47 strict IPv4 hosts entries are present"
else
    bad "missing hosts entries:$missing_hosts"
fi

if findmnt -n -o source /etc/hosts 2>/dev/null |
        grep -Fq 'tmpfs[/hosts.lg-block]'; then
    ok "custom hosts bind mount is active"
else
    bad "custom hosts bind mount is not active"
fi

section "Hardcoded IP routes"
for address in 156.147.69.32 54.186.247.229; do
    if ip route show type unreachable |
            awk -v expected="$address" \
                '$1 == "unreachable" && $2 == expected { found = 1 }
                 END { exit !found }'; then
        ok "$address has an unreachable route"
    else
        bad "$address is not blocked by an unreachable route"
    fi
done

section "Consent and ACR state"
if python3 - "$EULA_FILE" "$OPTION_FILE" "$GENERAL_FILE" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    eula = json.load(source)
with open(sys.argv[2]) as source:
    option = json.load(source)
with open(sys.argv[3]) as source:
    general = json.load(source)

status = eula.get("eulaStatus")
if not isinstance(status, dict):
    raise SystemExit(1)
allowed = [value for key, value in status.items() if key.endswith("Allowed")]
if not allowed or any(value is not False for value in allowed):
    raise SystemExit(1)

for section in ("eulaInfo", "eulaInfoNetwork"):
    for document in eula.get(section, {}).get("eulaList", []):
        if isinstance(document, dict) and "accepted" in document:
            if document["accepted"] is not False:
                raise SystemExit(1)

for key, expected in {
    "voiceAllowed": False,
    "voice2Allowed": False,
    "watchedListCollection": "off",
    "usageCare": False,
    "dbgLogUpload": False,
    "faultLogUpload": False,
    "thirdPartyCookie": "off",
}.items():
    if key in option and option[key] != expected:
        raise SystemExit(1)

for key, expected in {
    "aiNudge": "off",
    "screenSaverAd": "off",
    "homePromotion": "off",
    "launchEulaByHome": False,
}.items():
    if key in general and general[key] != expected:
        raise SystemExit(1)
PY
then
    ok "all available consent and data-collection settings are declined"
else
    bad "one or more consent settings are not declined"
fi

if [ -f "$ACR_DIR/eula_disallowed_rebooted" ] &&
        [ ! -e "$ACR_DIR/eula_allowed" ]; then
    ok "ACR opt-out marker is active"
else
    bad "ACR opt-out state is not active"
fi

section "App-update state"
update_state_ok=1
for file in "$UPDATE_BASE/updateInfo" \
            "$UPDATE_BASE/updateDependencyInfo"
do
    [ -s "$file" ] && update_state_ok=0
done

if [ "$update_state_ok" -eq 1 ]; then
    ok "app-update cache files are empty or absent"
else
    bad "one or more app-update cache files are non-empty"
fi

section "Live connectivity"
if command -v netstat >/dev/null 2>&1; then
    known_connections=$(
        netstat -tn 2>/dev/null |
            grep -E '54\.186\.247\.229|156\.147\.69\.32' || true
    )
    if [ -z "$known_connections" ]; then
        ok "no connections to known hardcoded LG endpoints"
    else
        bad "connection to a known hardcoded LG endpoint exists"
        echo "$known_connections" | sed 's/^/    /'
    fi
else
    info "netstat is unavailable; live connection check skipped"
fi

# This is informational: a temporary external failure should not invalidate
# the lockout itself. Success confirms that unrelated HTTPS remains available
# for third-party streaming applications.
if command -v wget >/dev/null 2>&1 &&
        command -v timeout >/dev/null 2>&1; then
    if timeout 8 wget -q -O /dev/null https://www.google.com; then
        info "general HTTPS connectivity is available"
    else
        info "general HTTPS connectivity test failed"
    fi
fi

echo
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
