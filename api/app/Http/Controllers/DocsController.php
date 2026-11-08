<?php

namespace App\Http\Controllers;

use Illuminate\Http\Response;

/**
 * Swagger UI para consultar y probar la API en desarrollo (DOCS_ENABLED=true).
 */
class DocsController extends Controller
{
    const SWAGGER_UI_VERSION = '5.17.14';

    public function index()
    {
        $cdn = 'https://cdn.jsdelivr.net/npm/swagger-ui-dist@'.self::SWAGGER_UI_VERSION;
        $specUrl = url('docs/openapi.yaml');

        $html = <<<HTML
<!doctype html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>MiRuta API</title>
  <link rel="stylesheet" href="{$cdn}/swagger-ui.css">
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="{$cdn}/swagger-ui-bundle.js"></script>
  <script>
    window.ui = SwaggerUIBundle({ url: "{$specUrl}", dom_id: "#swagger-ui" });
  </script>
</body>
</html>
HTML;

        return new Response($html, 200, ['Content-Type' => 'text/html; charset=utf-8']);
    }

    public function spec()
    {
        $path = config('miruta.openapi_path');

        if (! is_file($path)) {
            abort(404);
        }

        return new Response(file_get_contents($path), 200, ['Content-Type' => 'application/yaml; charset=utf-8']);
    }
}
