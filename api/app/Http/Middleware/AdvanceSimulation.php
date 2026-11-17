<?php

namespace App\Http\Middleware;

use App\Services\Simulations;
use Closure;
use Illuminate\Http\Request;

/**
 * Sin cron (docs/11 §11.66): cada petición con sesión hace avanzar la
 * simulación en curso hasta ahora (como mucho cada 3 s), antes de responder,
 * para que la app del Administrador vea su estado al día con solo consultar.
 */
class AdvanceSimulation
{
    public function handle(Request $request, Closure $next)
    {
        try {
            app(Simulations::class)->advance();
        } catch (\Throwable $e) {
            report($e);
        }

        return $next($request);
    }
}
