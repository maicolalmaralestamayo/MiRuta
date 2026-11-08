<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\JsonApi\MediaType;
use Closure;
use Illuminate\Http\Request;

/**
 * Exige la negociación de contenido de JSON:API y marca las respuestas con el
 * tipo application/vnd.api+json. Las rutas de subida de archivos (nombre
 * «subida.*») aceptan además multipart/form-data.
 */
class RequireJsonApi
{
    public function handle(Request $request, Closure $next)
    {
        if (! MediaType::isAcceptable($request->header('Accept'))) {
            throw new JsonApiException(406, 'NOT_ACCEPTABLE', 'Tipo no aceptable', 'La cabecera Accept debe admitir '.MediaType::JSON_API.'.');
        }

        $isUpload = $request->route() && $request->route()->named('subida.*');
        $isMultipart = $isUpload && stripos((string) $request->header('Content-Type'), 'multipart/form-data') === 0;

        if ($this->hasBody($request) && ! $isMultipart && ! MediaType::isValidContentType($request->header('Content-Type'))) {
            throw new JsonApiException(415, 'UNSUPPORTED_MEDIA_TYPE', 'Tipo de contenido no admitido', 'La petición debe enviarse con Content-Type: '.MediaType::JSON_API.'.');
        }

        $response = $next($request);

        if (stripos((string) $response->headers->get('Content-Type'), MediaType::JSON_API) !== 0) {
            $response->headers->set('Content-Type', MediaType::JSON_API);
        }

        return $response;
    }

    private function hasBody(Request $request): bool
    {
        return in_array($request->getMethod(), ['POST', 'PATCH', 'PUT'], true);
    }
}
