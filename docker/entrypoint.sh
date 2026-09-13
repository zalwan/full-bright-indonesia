#!/bin/sh
set -e

cd /var/www/html

# 1. .env: buat dari contoh bila belum ada
if [ ! -f .env ]; then
  echo "[entrypoint] .env tidak ada, copy dari .env.example"
  cp .env.example .env
fi

# 2. Selaraskan kredensial DB dengan service mysql compose.
# compose mengekspos DB_* sebagai real env vars, tapi .env file bisa
# menimpa tergantung urutan load — samakan keduanya agar deterministik.
set_val() { # $1=KEY $2=VALUE
  if grep -q "^$1=" .env; then
    sed -i "s|^$1=.*|$1=$2|" .env
  else
    printf '%s=%s\n' "$1" "$2" >> .env
  fi
}
if grep -q '^DB_HOST=127\.0\.0\.1' .env; then
  echo "[entrypoint] DB_* -> kredensial compose (db/pbm)"
fi
set_val DB_CONNECTION "${DB_CONNECTION:-mysql}"
set_val DB_HOST "${DB_HOST:-db}"
set_val DB_PORT "${DB_PORT:-3306}"
set_val DB_DATABASE "${DB_DATABASE:-pbm_landing_page}"
set_val DB_USERNAME "${DB_USERNAME:-pbm}"
set_val DB_PASSWORD "${DB_PASSWORD:-secret}"

# 3. Tunggu MySQL siap (max ~90 detik)
echo "[entrypoint] menunggu database ${DB_HOST:-db}..."
for i in $(seq 1 45); do
  if php artisan db:show --no-interaction >/dev/null 2>&1; then
    echo "[entrypoint] database siap."
    break
  fi
  if [ "$i" -eq 45 ]; then
    echo "[entrypoint] WARNING: database belum bisa diakses, lanjut (migrate mungkin gagal)."
  fi
  sleep 2
done

# 4. Dependencies (idempotent; cepat bila sudah terinstall)
if [ ! -f vendor/autoload.php ]; then
  echo "[entrypoint] composer install..."
  composer install --no-interaction --prefer-dist
fi
if [ ! -d node_modules/.bin ]; then
  echo "[entrypoint] npm ci..."
  npm ci --no-audit --no-fund
fi

# 5. Laravel setup
php artisan key:generate --no-interaction --force || true
php artisan migrate --force --no-interaction
php artisan storage:link --no-interaction || true
php artisan optimize:clear --no-interaction || true

echo "[entrypoint] up: http://localhost:8000 (vite HMR :5175)"

# 6. Jalankan server + vite bersamaan (bind 0.0.0.0 agar bisa diakses dari host)
exec npx concurrently -c "#93c5fd,#fdba74" \
  "php artisan serve --host=0.0.0.0 --port=8000" \
  "npm run dev -- --host 0.0.0.0 --port 5175" \
  --names='server,vite'
