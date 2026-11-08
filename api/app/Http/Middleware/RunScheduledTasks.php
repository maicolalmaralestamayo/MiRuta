<?php

namespace App\Http\Middleware;

use App\Services\ScheduledTasks;
use Closure;
use Illuminate\Http\Request;

/**
 * Sin cron (hospedaje compartido): al terminar cada petición se ejecutan las
 * tareas programadas pendientes, como mucho una vez por minuto. Se activa con
 * TASKS_ON_REQUESTS=true.
 */
class RunScheduledTasks
{
    public function handle(Request $request, Closure $next)
    {
        return $next($request);
    }

    public function terminate($request, $response): void
    {
        if (! config('miruta.tasks_on_requests') || app()->runningUnitTests()) {
            return;
        }

        // Que la app reciba ya su respuesta y no espere a las tareas.
        if (function_exists('fastcgi_finish_request')) {
            fastcgi_finish_request();
        }

        ignore_user_abort(true);

        try {
            app(ScheduledTasks::class)->runDue(true);
        } catch (\Throwable $e) {
            report($e);
        }
    }
}
