# PHP 8.2 (la del hospedaje) para probar la API en un PC.
FROM php:8.2-cli
RUN apt-get update && apt-get install -y --no-install-recommends libzip-dev unzip && rm -rf /var/lib/apt/lists/* \
    && docker-php-ext-install pdo_mysql zip
WORKDIR /repo/api
