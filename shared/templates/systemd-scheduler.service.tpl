[Unit]
Description=Tenant Scheduler Runner
After=network.target

[Service]
Type=oneshot
User={{APP_USER}}
Group={{APP_GROUP}}
WorkingDirectory={{APP_ROOT}}
ExecStart={{PHP_BIN}} artisan schedule:run
