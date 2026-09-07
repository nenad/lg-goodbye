#!/bin/sh
#
# Clear LG Content Store's cached app-update state.
#
# The strict hosts block disables the Content Store, while these cache files
# can still produce stale update prompts. Non-empty files are moved to
# timestamped backups and replaced with empty files.

set -eu

BASE=/mnt/lg/cmn_data/var/palm/data/com.webos.appInstallService
TIMESTAMP=$(date +%Y%m%d%H%M%S)
DRY_RUN=0

[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

log() {
    echo "[clear-app-update-gate] $*" >&2
}

if [ ! -d "$BASE" ]; then
    log "app-install state directory is absent; nothing to clear"
    exit 0
fi

for file in "$BASE/updateInfo" "$BASE/updateDependencyInfo"; do
    if [ -s "$file" ]; then
        if [ "$DRY_RUN" -eq 1 ]; then
            log "would move aside non-empty file: $file"
        else
            mv "$file" "$file.bak.$TIMESTAMP"
            : > "$file"
            log "cleared: $file"
        fi
    elif [ ! -e "$file" ] && [ "$DRY_RUN" -eq 0 ]; then
        : > "$file"
        log "created empty state file: $file"
    else
        log "already empty: $file"
    fi
done

exit 0
