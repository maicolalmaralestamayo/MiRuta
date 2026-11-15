<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Consultas condicionales (docs/11 §11.62, caché local de la app): cada GET
 * correcto lleva ETag (huella del contenido). Si la app envía If-None-Match
 * con la huella que ya tiene, se responde 304 sin cuerpo: solo viaja lo que
 * cambió y la app usa lo guardado.
 */
class ConditionalGet
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        if (! $request->isMethod('GET') || $response->getStatusCode() !== 200) {
            return $response;
        }

        $content = $response->getContent();

        if ($content === false || $content === '') {
            return $response;
        }

        $etag = '"'.md5($content).'"';
        $response->headers->set('ETag', $etag);

        $sent = array_map('trim', explode(',', (string) $request->headers->get('If-None-Match', '')));

        if (in_array($etag, $sent, true) || in_array('W/'.$etag, $sent, true)) {
            $response->setNotModified();
        }

        return $response;
    }
}
