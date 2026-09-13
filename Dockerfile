# Dev + prod-build image: PHP 8.4 CLI (artisan serve + vite dev) + Node 22 + Composer.
# composer.lock butuh PHP >=8.4.1 (Laravel 13 + Symfony 8.1).
# Tidak butuh PHP di host. Jalankan: docker compose up --build
FROM php:8.4-cli-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_HOME=/root/.composer

# System deps + PHP extensions yang dibutuhkan Laravel 13
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl zip unzip \
        libpng-dev libjpeg-dev libwebp-dev libonig-dev libxml2-dev \
        libzip-dev libicu-dev libcurl4-openssl-dev default-mysql-client \
    && docker-php-ext-configure gd --with-jpeg --with-webp \
    && docker-php-ext-install -j$(nproc) \
        pdo_mysql mbstring exif pcntl bcmath gd zip intl opcache \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Node.js 22 (untuk Vite dev/build)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && node -v && npm -v

# Composer 2 dari image resmi
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html

# Cache layer: install PHP deps dulu sebelum copy source
COPY composer.json composer.lock ./
RUN composer install --no-interaction --no-scripts --no-autoloader --prefer-dist

# Cache layer: install JS deps (package-lock ikut agar npm ci reproducible)
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY . .

RUN composer dump-autoload --optimize \
    && chmod +x docker/entrypoint.sh

EXPOSE 8000 5175

ENTRYPOINT ["docker/entrypoint.sh"]
