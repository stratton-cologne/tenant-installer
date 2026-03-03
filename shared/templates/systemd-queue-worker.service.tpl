[Unit]
Description=Tenant Queue Worker
After=network.target

[Service]
Type=simple
User={{APP_USER}}
Group={{APP_GROUP}}
WorkingDirectory={{APP_ROOT}}
ExecStart={{PHP_BIN}} artisan queue:work --sleep=3 --tries=3 --timeout=90
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
