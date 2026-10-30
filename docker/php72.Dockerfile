# PHP 7.2 para ejecutar la API y sus pruebas con la misma versión mínima que el servidor
FROM php:7.2-cli
RUN docker-php-ext-install pdo_mysql
WORKDIR /app
