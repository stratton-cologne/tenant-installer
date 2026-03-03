[program:tenant-queue-worker]
command={{PHP_BIN}} {{APP_ROOT}}/artisan queue:work --sleep=3 --tries=3 --timeout=90
directory={{APP_ROOT}}
user={{APP_USER}}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
numprocs=1
redirect_stderr=true
stdout_logfile={{LOG_DIR}}/queue-worker.log
stopwaitsecs=3600
