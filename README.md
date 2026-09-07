# LG Goodbye

Installs a persistent network and privacy lockout on rooted LG webOS TVs while
leaving unrelated internet traffic available for third-party streaming apps.

## Root and SSH setup

The TV must be jailbroken (rooted) before this installer can be used. Check
your model and firmware compatibility at
[cani.rootmy.tv](https://cani.rootmy.tv/) and follow the linked rooting
instructions.

After rooting:

1. Open Homebrew Channel on the TV and enable its SSH server.
2. Connect from your computer with `ssh root@TV_IP`.
3. The initial root password is `alpine`.
4. Install an SSH public key before running this installer. It deliberately
   uses non-interactive SSH and will not prompt for a password.

The default password is publicly known. Keep SSH limited to your trusted local
network and replace password access with a key as soon as possible.

## Requirements

- A rooted LG webOS TV running Homebrew Channel
- Root SSH access using keys
- `ssh`, `scp`, and Bash on the computer running the installer
- The TV must be reachable over the local network

## Install

From this directory, provide one or more TV IP addresses:

```bash
./install.sh 192.168.178.138 192.168.178.33
```

An address without a username automatically uses `root`. The equivalent
explicit form is:

```bash
./install.sh root@192.168.178.138
```

To reboot each TV and verify that the protection survives startup:

```bash
./install.sh --reboot 192.168.178.138 192.168.178.33
```

The installer is idempotent and can be run again to update or repair an
existing installation.

## What it installs

- `10-block-lg-telemetry` — bind-mounts a strict 47-domain LG hosts blocklist.
- `20-block-lg-ips` — rejects two known hardcoded LG endpoint IP addresses.
- `30-enforce-lg-privacy` — reapplies consent, ACR, and update-cache settings
  immediately and again 30 seconds after startup.
- `decline-tos.sh` — declines supported LG consent and collection settings.
- `clear-app-update-gate.sh` — clears cached LG app-update prompts.
- `verify-lockout.sh` — performs read-only verification.

Homebrew Channel runs the numbered scripts from
`/var/lib/webosbrew/init.d/` at every startup.

## Important behavior

This is the strict configuration. It blocks LG Content Store, LG Shop, LG
voice search, telemetry, advertising, ThinQ, AI endpoints, and OS updates.
Existing third-party streaming apps can still use unrelated internet
destinations, but installing or updating them through LG Content Store will
not work while this configuration is active.

The hardcoded IP list can become outdated if LG changes its infrastructure.
Run the verifier periodically and review the scripts before using them on a
different webOS generation.

## Verification

The installer runs verification automatically. To run it again manually:

```bash
ssh root@192.168.178.138 \
  'sh /var/lib/webosbrew/lg-lockout/verify-lockout.sh'
```

A healthy installation ends with `0 failed`. General HTTPS connectivity is
reported for information but does not change the lockout result.

## Backups and recovery

Before deployment, the installer creates a backup on each TV under:

```text
/tmp/lg-lockout-backup.YYYYMMDDhhmmss
```

Consent changes also create timestamped backups beside the original preference
files. `/tmp` backups disappear after reboot.

A factory reset removes Homebrew, root access, and all on-TV lockout changes.
The startup scripts do not protect the TV before Homebrew starts and do not
survive a factory reset.
