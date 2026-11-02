# Imagen de la API de MiRuta con el código y sus dependencias ya dentro, para
# usarla sin Internet (docker load). Se construye desde la raíz del repositorio:
#   docker build -f docker/offline/Dockerfile -t miruta-api:2.2.0 .
FROM php:7.2-cli
RUN docker-php-ext-install pdo_mysql
COPY api /app
COPY docker/offline/start.sh /start.sh
# El servidor de PHP del contenedor corre como root: no hace falta cambiar permisos.
COPY docs/openapi.yaml /docs/openapi.yaml
ENV OPENAPI_PATH=/docs/openapi.yaml
WORKDIR /app
EXPOSE 8000
CMD ["sh", "/start.sh"]
