# Image for Appdonia - platform deployment.
# Everything is built in: PHP dependencies and frontend assets. Nothing is
# downloaded or compiled when a container starts.

FROM dunglas/frankenphp

# curl: healthcheck. procps: pgrep/ps for debugging and healthchecks.
RUN apt-get update && apt-get install -y \
    curl git unzip procps \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ADAPT: match the project's database driver and composer.json "ext-*" needs.
RUN install-php-extensions \
    pcntl \
    pdo_mysql \
    zip \
    mbstring \
    bcmath \
    gd \
    intl \
    exif \
    opcache

COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

WORKDIR /var/www

# Dependency manifests first, so these layers are cached between builds.
# --no-scripts: Laravel's composer scripts need the app code and an .env.
COPY composer.json composer.lock ./
RUN composer install \
    --no-dev \
    --no-interaction \
    --no-scripts \
    --prefer-dist

# ADAPT: remove the npm steps if the project has no frontend build.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

RUN composer dump-autoload --optimize --no-dev --no-scripts \
    && npm run build \
    && rm -rf node_modules

RUN mkdir -p storage/framework/sessions storage/framework/views storage/framework/cache/data \
        storage/logs bootstrap/cache \
    && chown -R www-data:www-data /var/www \
    && chmod -R 775 storage bootstrap/cache

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# The web server listens here; override with APP_PORT or PORT.
EXPOSE 8000

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["web"]
