FROM php:8.3-fpm

RUN apt-get update && apt-get install -y \
    zip unzip curl git libpng-dev libonig-dev libxml2-dev libzip-dev \
    libcurl4-openssl-dev libssl-dev libicu-dev libxslt1-dev \
    && docker-php-ext-install pdo_mysql mbstring zip exif pcntl gd intl \
    && pecl install redis \
    && docker-php-ext-enable redis \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www
COPY ../../laravel .

ENV DISABLE_PACKAGE_DISCOVER=1
RUN composer install --no-dev --optimize-autoloader --no-interaction

RUN chmod -R 775 storage bootstrap/cache && chown -R www-data:www-data .
RUN sed -i 's|^listen = .*|listen = 0.0.0.0:9000|' /usr/local/etc/php-fpm.d/www.conf

CMD bash -c "\
  unset DISABLE_PACKAGE_DISCOVER && \
  [ ! -f .env ] && cp .env.example .env && \
  php artisan package:discover --ansi && \
  php artisan config:clear && php artisan config:cache && \
  php artisan route:clear && php artisan route:cache && \
  php artisan migrate --force && \
  exec php-fpm"
