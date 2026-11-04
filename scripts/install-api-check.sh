#!/bin/sh
# Runs scripts/check_apis.py on the 1st of each month; if the computer was off,
# on the next time it is on. See docs/APIS.md.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$units"

cat > "$units/aupp-api-check.service" <<UNIT
[Unit]
Description=AUPP: confere as APIs usadas pelo app

[Service]
Type=oneshot
ExecStart=/usr/bin/python3 "$root/scripts/check_apis.py"
SuccessExitStatus=1
UNIT

cat > "$units/aupp-api-check.timer" <<UNIT
[Unit]
Description=AUPP: confere as APIs uma vez por mês

[Timer]
OnCalendar=*-*-01 10:00
Persistent=true

[Install]
WantedBy=timers.target
UNIT

systemctl --user daemon-reload
systemctl --user enable --now aupp-api-check.timer
systemctl --user list-timers aupp-api-check.timer --no-pager
