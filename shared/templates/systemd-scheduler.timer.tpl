[Unit]
Description=Run Tenant Scheduler Every Minute

[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true

[Install]
WantedBy=timers.target
