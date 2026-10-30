<?php

namespace App\Http\Middleware;

use App\JsonApi\JsonApiException;
use App\Models\Worker;
use App\Services\TokenService;
use Closure;
use Illuminate\Http\Request;

/**
 * Exige un token de acceso válido de un trabajador activo.
 */
class Authenticate
{
    /** @var TokenService */
    private $tokens;

    public function __construct(TokenService $tokens)
    {
        $this->tokens = $tokens;
    }

    public function handle(Request $request, Closure $next)
    {
        $token = $request->bearerToken();

        if (! $token) {
            throw new JsonApiException(401, 'UNAUTHENTICATED', 'No autenticado', 'Falta la cabecera Authorization: Bearer <token>.');
        }

        $claims = $this->tokens->decodeAccess($token);
        $worker = Worker::find($claims['sub']);

        if (! $worker) {
            throw new JsonApiException(401, 'TOKEN_REVOKED', 'Token revocado', 'La cuenta está desactivada.');
        }

        $worker->setCurrentSessionId(isset($claims['sid']) ? (int) $claims['sid'] : null);
        app('auth')->guard()->setUser($worker);
        $request->setUserResolver(function () use ($worker) {
            return $worker;
        });

        return $next($request);
    }
}
