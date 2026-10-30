# Definición de Hecho (*Definition of Done*)

Una historia de usuario está **hecha** solo cuando cumple **todo** lo siguiente.

## Código

- [ ] Cumple todos sus criterios de aceptación.
- [ ] La API sigue las convenciones de Laravel y el patrón modelo-controlador, y es compatible con PHP 7.2.5.
- [ ] Las respuestas cumplen JSON:API, y los errores usan los `code` documentados.
- [ ] Los permisos por rol están aplicados en las *Policies*. Los datos privados (carné, fechas de nacimiento) no aparecen donde no deben.
- [ ] La app muestra todos sus textos en español.
- [ ] No hay valores fijos en el código que deberían ser un ajuste.

## Base de datos

- [ ] Hay migración (con `down` funcional), y *seeder* o *factory* si hace falta.
- [ ] Las tablas nuevas cumplen la 3FN y tienen `created_at`, `updated_at` y `deleted_at`.

## Pruebas

- [ ] Pruebas automáticas de la API (PHPUnit) para el caso normal, los errores y los permisos de la historia.
- [ ] Pruebas de la lógica de la app (`flutter test`) cuando hay reglas o cálculos en el teléfono.
- [ ] Todas las pruebas existentes pasan.
- [ ] Probado a mano en un teléfono Android real o emulado.

## Documentación

- [ ] `docs/openapi.yaml` está actualizado y es válido.
- [ ] Los documentos de `docs/` reflejan cualquier cambio de reglas, datos o pantallas.

## Integración

- [ ] Está integrado en la rama principal mediante *pull request*.
- [ ] Desplegado en el entorno de pruebas.
- [ ] El Product Owner lo vio en la Sprint Review.
