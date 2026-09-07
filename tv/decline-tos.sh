#!/bin/sh
#
# Decline LG consent, telemetry, voice, advertising, and ACR settings.
#
# Every changed preference file receives a timestamped backup beside the
# original. Use --dry-run to check prerequisites without writing anything.

set -eu

EULA_FILE=/var/luna/preferences/eula
OPTION_FILE=/var/luna/preferences/option
GENERAL_FILE=/var/luna/preferences/general
ACR_DIR=/mnt/lg/cmn_data/acr/data
ACR_OPTOUT="$ACR_DIR/eula_disallowed_rebooted"
DRY_RUN=0
TIMESTAMP=$(date +%Y%m%d%H%M%S)

[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log() {
    echo "[decline-tos] $*" >&2
}

command -v python3 >/dev/null 2>&1 || {
    log "fatal: python3 is required to update JSON safely"
    exit 1
}

for file in "$EULA_FILE" "$OPTION_FILE" "$GENERAL_FILE"; do
    [ -f "$file" ] || {
        log "fatal: required preference file is missing: $file"
        exit 1
    }
done

if [ "$DRY_RUN" -eq 1 ]; then
    log "would decline all supported EULA and option consent settings"
    log "would create the ACR opt-out marker"
    log "would reload eula-service"
    exit 0
fi

cp -p "$EULA_FILE" "$EULA_FILE.bak.$TIMESTAMP"
python3 - "$EULA_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as source:
    data = json.load(source)

for key in list(data.get("eulaStatus", {})):
    if key.endswith("Allowed"):
        data["eulaStatus"][key] = False

for section in ("eulaInfo", "eulaInfoNetwork"):
    documents = data.get(section, {}).get("eulaList")
    if isinstance(documents, list):
        for document in documents:
            if isinstance(document, dict) and "accepted" in document:
                document["accepted"] = False
                document["updated"] = True

with open(path, "w") as destination:
    json.dump(data, destination, indent=2)
PY
log "declined EULA consent state"

cp -p "$OPTION_FILE" "$OPTION_FILE.bak.$TIMESTAMP"
python3 - "$OPTION_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as source:
    data = json.load(source)

expected = {
    "voiceAllowed": False,
    "voice2Allowed": False,
    "watchedListCollection": "off",
    "usageCare": False,
    "dbgLogUpload": False,
    "faultLogUpload": False,
    "thirdPartyCookie": "off",
}
for key, value in expected.items():
    # Some webOS models omit unsupported keys. Do not invent settings that the
    # model's settings service does not understand.
    if key in data:
        data[key] = value

with open(path, "w") as destination:
    json.dump(data, destination, indent=2)
PY
log "disabled supported data-collection options"

cp -p "$GENERAL_FILE" "$GENERAL_FILE.bak.$TIMESTAMP"
python3 - "$GENERAL_FILE" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as source:
    data = json.load(source)

expected = {
    "aiNudge": "off",
    "screenSaverAd": "off",
    "homePromotion": "off",
    "launchEulaByHome": False,
}
for key, value in expected.items():
    if key in data:
        data[key] = value

with open(path, "w") as destination:
    json.dump(data, destination, indent=2)
PY
log "disabled supported advertising and nudge options"

mkdir -p "$ACR_DIR"
if [ -e "$ACR_DIR/eula_allowed" ]; then
    mv "$ACR_DIR/eula_allowed" \
        "$ACR_DIR/eula_allowed.bak.$TIMESTAMP"
fi
: > "$ACR_OPTOUT"
log "created ACR opt-out marker"

# eula-service is a dynamic Luna service rather than a systemd unit. Luna
# starts it again on demand, at which point it reads the updated preferences.
pids=$(pgrep -x eula-service 2>/dev/null || true)
if [ -n "$pids" ]; then
    kill $pids 2>/dev/null || true
    log "requested eula-service reload"
fi

exit 0
