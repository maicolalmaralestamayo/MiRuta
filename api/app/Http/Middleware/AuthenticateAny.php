<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;

/**
 * Con sesión (Authorization: Bearer) o, si no, con la instalación (X-Installation).
 */
class AuthenticateAny
{
    public function handle(Request $request, Closure $next)
    {
        return $request->bearerToken()
            ? app(Authenticate::class)->handle($request, $next)
            : app(AuthenticateInstallation::class)->handle($request, $next);
    }
}
