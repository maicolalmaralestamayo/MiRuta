<?php

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Tareas programadas, sin cron (hospedaje compartido sin SSH):
 *
 * - con TASKS_ON_REQUESTS=true la API ejecuta las pendientes al terminar las
 *   peticiones, como mucho una vez por minuto;
 * - el Administrador también las ejecuta desde la app (Mantenimiento del
 *   servidor → «run-tasks»);
 * - con cron (opcional): php artisan miruta:tareas cada minuto.
 *
 * Las diarias y por hora no se pierden si nadie usa la app a esa hora: se
 * ejecutan en la primera revisión posterior.
 */
class ScheduledTasks
{
    /**
     * Nombre => [frecuencia ('minute', 'hour' o 'HH:MM'), [servicio, método]].
     */
    public const TASKS = [
        'viajes:revisar' => ['minute', [Trips::class, 'review']],
        'olvide:caducar' => ['hour', [AccessRecoveries::class, 'expireOld']],
        'qr:limpiar' => ['hour', [QrCodes::class, 'purgeExpiredNonces']],
        'conversaciones:limpiar' => ['02:10', [Conversations::class, 'purgeOld']],
        'notificaciones:limpiar' => ['02:20', [Notifier::class, 'purgeOld']],
    ];

    public function statePath(): string
    {
        return storage_path('app/tareas-programadas.json');
    }

    /**
     * Estado guardado: tarea => ['lastRun', 'lastAttempt', 'ok', 'error'].
     */
    public function state(): array
    {
        $path = $this->statePath();
        $data = is_file($path) ? json_decode((string) file_get_contents($path), true) : null;

        return is_array($data) ? $data : [];
    }

    public function isDue(string $frequency, ?Carbon $lastRun, Carbon $now): bool
    {
        if ($lastRun === null) {
            return true;
        }

        if ($frequency === 'minute') {
            return $lastRun->copy()->startOfMinute()->lt($now->copy()->startOfMinute());
        }

        if ($frequency === 'hour') {
            return $lastRun->copy()->startOfHour()->lt($now->copy()->startOfHour());
        }

        [$hour, $minute] = array_map('intval', explode(':', $frequency));
        $scheduled = $now->copy()->setTime($hour, $minute);

        if ($scheduled->gt($now)) {
            $scheduled->subDay();
        }

        return $lastRun->lt($scheduled);
    }

    /**
     * Ejecuta las tareas pendientes (si otra petición ya lo está haciendo, nada).
     *
     * @param bool $onlyIfMinutePassed para las peticiones: como mucho una vez por minuto
     * @return array tarea => ['ok' => bool, 'error' => ?string, 'result' => mixed]
     */
    public function runDue(bool $onlyIfMinutePassed = false): array
    {
        $directory = dirname($this->statePath());

        if (! is_dir($directory)) {
            @mkdir($directory, 0775, true);
        }

        $lock = @fopen($directory.'/tareas-programadas.lock', 'c');

        if ($lock === false || ! flock($lock, LOCK_EX | LOCK_NB)) {
            return [];
        }

        try {
            $now = Carbon::now();
            $state = $this->state();
            $lastCheck = isset($state['_lastCheck']) ? Carbon::parse($state['_lastCheck']) : null;

            if ($onlyIfMinutePassed && $lastCheck !== null && $lastCheck->copy()->startOfMinute()->eq($now->copy()->startOfMinute())) {
                return [];
            }

            $state['_lastCheck'] = $now->toIso8601String();
            $this->save($state);
            $results = [];

            // Sin base de datos instalada no hay nada que hacer.
            if (! Schema::hasTable('users')) {
                return [];
            }

            foreach (self::TASKS as $name => [$frequency, $callable]) {
                $lastRun = isset($state[$name]['lastRun']) ? Carbon::parse($state[$name]['lastRun']) : null;

                if (! $this->isDue($frequency, $lastRun, $now)) {
                    continue;
                }

                $results[$name] = $this->run($callable);
                $state[$name] = [
                    'lastRun' => $results[$name]['ok'] ? $now->toIso8601String() : $lastRun?->toIso8601String(),
                    'lastAttempt' => $now->toIso8601String(),
                    'ok' => $results[$name]['ok'],
                    'error' => $results[$name]['error'],
                ];
                $this->save($state);
            }

            return $results;
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    private function run(array $callable): array
    {
        try {
            $result = app($callable[0])->{$callable[1]}();

            return ['ok' => true, 'error' => null, 'result' => $result];
        } catch (\Throwable $e) {
            Log::error('Tarea programada '.$callable[0].'::'.$callable[1].': '.$e->getMessage(), ['exception' => $e]);

            return ['ok' => false, 'error' => $e->getMessage(), 'result' => null];
        }
    }

    private function save(array $state): void
    {
        @file_put_contents($this->statePath(), json_encode($state, JSON_PRETTY_PRINT), LOCK_EX);
    }
}
