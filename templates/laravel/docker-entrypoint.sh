#!/bin/sh
#
# Container entrypoint for Appdonia - platform deployment.
#
# The app is configured entirely from environment variables. There is no
# install wizard: on boot the web container migrates and seeds the database
# and creates the admin user from ADMIN_EMAIL / ADMIN_PASSWORD.
#
# Commands:
#   web (default)     web server; also runs the queue worker and scheduler
#                     unless RUN_QUEUE_WORKER / RUN_SCHEDULER are "false"
#   queue             dedicated queue worker
#   scheduler         dedicated scheduler
#   <anything else>   executed as-is
#
# Setup steps don't abort the boot on failure, so the web server still starts
# and the logs show what went wrong.

APP_DIR="${APP_DIR:-/var/www}"
cd "$APP_DIR" || {
    echo "ERROR: Cannot change to $APP_DIR"
    exit 1
}

ROLE="${1:-web}"
case "$ROLE" in
    web|octane|frankenphp) IS_WEB=true ;;
    *) IS_WEB=false ;;
esac

WEB_USER="${WEB_USER:-www-data}"
LISTEN_PORT="${APP_PORT:-${PORT:-8000}}"

# --------------------------------------------------------------------------
# Writable directories (storage and uploads are usually mounted volumes, which
# arrive empty and owned by root on the first deploy)
# --------------------------------------------------------------------------
echo "Preparing writable directories..."
# ADAPT: list any other directories the app writes to (upload folders outside
# storage/), space separated, relative to the app directory.
EXTRA_WRITABLE_DIRS=""
mkdir -p \
    storage/app/public \
    storage/framework/sessions \
    storage/framework/views \
    storage/framework/cache/data \
    storage/logs \
    bootstrap/cache \
    $EXTRA_WRITABLE_DIRS
chown -R "$WEB_USER":"$WEB_USER" storage bootstrap/cache $EXTRA_WRITABLE_DIRS 2>/dev/null || true
chmod -R 775 storage bootstrap/cache $EXTRA_WRITABLE_DIRS 2>/dev/null || true

# --------------------------------------------------------------------------
# .env file. Real environment variables always win over values in this file,
# so it only provides defaults for anything the deployment doesn't set.
#
# If the app saves settings into .env, they must survive redeploys, so the
# file lives in the storage volume and /var/www/.env is a symlink to it. A
# real .env file (e.g. bind-mounted in development) is used as-is.
# --------------------------------------------------------------------------
ENV_FILE="storage/.env"
if [ -f ".env" ] && [ ! -L ".env" ]; then
    echo "Using existing .env file."
else
    if [ ! -f "$ENV_FILE" ]; then
        echo "Creating default $ENV_FILE..."
        # ADAPT: defaults the app needs when a variable is not set.
        cat > "$ENV_FILE" <<EOF
APP_NAME="${APP_NAME:-App}"
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://localhost

LOG_CHANNEL=daily
LOG_LEVEL=warning

DB_CONNECTION=mysql
DB_HOST=db
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=laravel
DB_PASSWORD=

CACHE_STORE=file
CACHE_DRIVER=file
FILESYSTEM_DISK=local
QUEUE_CONNECTION=database
SESSION_DRIVER=file
SESSION_LIFETIME=120
EOF
    fi
    ln -sfn "$ENV_FILE" .env
    chown "$WEB_USER":"$WEB_USER" "$ENV_FILE" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
# APP_KEY. Prefer the environment variable. Otherwise generate one once and
# keep it in the storage volume so sessions and encrypted data survive
# redeploys, and every container sharing the volume uses the same key.
# --------------------------------------------------------------------------
if [ -z "$APP_KEY" ] || [ "$APP_KEY" = "base64:" ]; then
    KEY_FILE="storage/app/.app_key"
    if [ ! -s "$KEY_FILE" ]; then
        echo "APP_KEY not set - generating one and storing it in $KEY_FILE"
        php -r 'echo "base64:".base64_encode(random_bytes(32));' > "$KEY_FILE"
        chmod 600 "$KEY_FILE"
    fi
    APP_KEY="$(cat "$KEY_FILE")"
    export APP_KEY
fi

# A config cache left over from a previous start would hide new env values.
rm -f bootstrap/cache/config.php

# --------------------------------------------------------------------------
# Wait for the database
# --------------------------------------------------------------------------
if [ -n "$DB_HOST" ] && [ "$DB_HOST" != "localhost" ] && [ "$DB_HOST" != "127.0.0.1" ]; then
    echo "Waiting for database at ${DB_HOST}:${DB_PORT:-default port}..."
    attempt=0
    until php -r '
        $driver = getenv("DB_CONNECTION") === "pgsql" ? "pgsql" : "mysql";
        $port = getenv("DB_PORT") ?: ($driver === "pgsql" ? "5432" : "3306");
        $dsn = "$driver:host=" . getenv("DB_HOST") . ";port=$port";
        if ($driver === "pgsql") {
            $dsn .= ";dbname=" . getenv("DB_DATABASE");
        }
        try {
            new PDO($dsn, getenv("DB_USERNAME"), getenv("DB_PASSWORD"));
            exit(0);
        } catch (Throwable $e) {
            exit(1);
        }' 2>/dev/null; do
        attempt=$((attempt + 1))
        if [ $attempt -ge 60 ]; then
            echo "Database still unavailable after $attempt attempts. Continuing anyway..."
            break
        fi
        echo "Database is unavailable - sleeping (attempt $attempt/60)"
        sleep 2
    done
fi

# --------------------------------------------------------------------------
# Setup on every boot (web container only, so containers never race on the
# schema). Every step is safe to repeat.
# --------------------------------------------------------------------------
if [ "$IS_WEB" = true ]; then
    echo "Running migrations..."
    php artisan migrate --force || echo "Migrations failed"

    echo "Seeding database (first boot only)..."
    php artisan db:seed-if-needed || echo "Seeding failed"

    # ADAPT: project-specific setup (module migrations, imports, ...), each
    # followed by: || echo "... failed"

    echo "Ensuring admin user..."
    php artisan app:ensure-admin || echo "Admin user creation failed"

    php artisan storage:link >/dev/null 2>&1 || true

    echo "Caching configuration, routes and views..."
    php artisan optimize:clear >/dev/null 2>&1 || true
    php artisan config:cache || echo "Config cache failed"
    php artisan route:cache || echo "Route cache failed"
    php artisan view:cache || echo "View cache failed"

    chown -R "$WEB_USER":"$WEB_USER" storage bootstrap/cache 2>/dev/null || true

    echo "App initialization complete!"
fi

# --------------------------------------------------------------------------
# Start the requested process
# --------------------------------------------------------------------------
case "$ROLE" in
    web|octane|frankenphp)
        # queue:work exits after --max-time, so keep restarting it.
        if [ "${RUN_QUEUE_WORKER:-true}" != "false" ]; then
            echo "Starting queue worker in background..."
            ( while true; do php artisan queue:work --sleep=3 --tries=3 --max-time=3600; sleep 2; done ) &
        fi
        if [ "${RUN_SCHEDULER:-true}" != "false" ]; then
            echo "Starting scheduler in background..."
            ( while true; do php artisan schedule:work; sleep 2; done ) &
        fi

        # ADAPT: if the image ships its own web server (e.g. nginx + php-fpm
        # under supervisord), replace this block with: exec <its start command>
        if [ -d vendor/laravel/octane ]; then
            echo "Starting Octane (FrankenPHP) on port $LISTEN_PORT..."
            exec php artisan octane:start --server=frankenphp --host=0.0.0.0 --port="$LISTEN_PORT"
        elif command -v frankenphp >/dev/null 2>&1; then
            echo "Starting FrankenPHP on port $LISTEN_PORT..."
            exec frankenphp php-server --root public --listen ":$LISTEN_PORT"
        else
            echo "WARNING: no production web server found, falling back to artisan serve"
            exec php artisan serve --host=0.0.0.0 --port="$LISTEN_PORT"
        fi
        ;;
    queue|queue:work)
        echo "Starting queue worker..."
        exec php artisan queue:work --sleep=3 --tries=3 --max-time=3600
        ;;
    scheduler|schedule:work)
        echo "Starting scheduler..."
        exec php artisan schedule:work
        ;;
    *)
        echo "Starting: $*"
        exec "$@"
        ;;
esac
