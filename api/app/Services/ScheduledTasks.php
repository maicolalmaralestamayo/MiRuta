<?php

namespace App\Services;

use Carbon\Carbon;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Schema;

/**
 * Tareas programadas (docs/02-procesos.md §2.13).
 *
 * Hay dos formas de ejecutarlas:
 *  - con cron: "php artisan schedule:run" cada minuto (Console\Kernel usa esta lista);
 *  - sin cron (hospedaje compartido sin SSH): con TASKS_ON_REQUESTS=true la API
 *    ejecuta las pendientes al terminar las peticiones, como mucho una vez por
 *    minuto. Las diarias y por hora no se pierden si nadie usa la app a esa
 *    hora: se ejecutan en la primera petición posterior.
 */
class ScheduledTasks
{
    /**
     * Comando => frecuencia: 'minute', 'hour' o una hora del día 'HH:MM'.
     */
    public const TASKS = [
        'trips:auto-complete' => 'minute',
        'trips:notify-delays' => 'minute',
        'chats:purge-trips' => 'minute',
        'chats:purge-expired' => '02:10',
        'workers:inactivity' => '02:20',
        'access-recoveries:expire' => 'hour',
        'passwords:warn-expiry' => '07:00',
    ];

    public function statePath(): string
    {
        return storage_path('app/tareas-programadas.json');
    }

    /**
     * Estado guardado: comando => ['lastRun' => última vez que terminó bien,
     * 'lastAttempt' => última vez que se intentó, 'ok' => bool, 'error' => ?string].
     */
    public function state(): array
    {
        $path = $this->statePath();
        $data = is_file($path) ? json_decode((string) file_get_contents($path), true) : null;

        return is_array($data) ? $data : [];
    }

    /**
     * Si la tarea toca ahora, según cuándo se ejecutó por última vez.
     */
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
     * Ejecuta las tareas pendientes. Si otra petición ya las está
     * ejecutando, no hace nada. Devuelve comando => resultado.
     *
     * @param bool $onlyIfMinutePassed para las peticiones: como mucho una vez por minuto
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

            foreach (self::TASKS as $command => $frequency) {
                $lastRun = isset($state[$command]['lastRun']) ? Carbon::parse($state[$command]['lastRun']) : null;

                if (! $this->isDue($frequency, $lastRun, $now)) {
                    continue;
                }

                // Si falla, se reintenta en la próxima revisión (lastRun no cambia).
                $results[$command] = $this->run($command);
                $state[$command] = [
                    'lastRun' => $results[$command]['ok'] ? $now->toIso8601String() : ($lastRun ? $lastRun->toIso8601String() : null),
                    'lastAttempt' => $now->toIso8601String(),
                ] + $results[$command];
                $this->save($state);
            }

            return $results;
        } finally {
            flock($lock, LOCK_UN);
            fclose($lock);
        }
    }

    /**
     * @return array{ok: bool, error: ?string}
     */
    private function run(string $command): array
    {
        try {
            Artisan::call($command);

            return ['ok' => true, 'error' => null];
        } catch (\Throwable $e) {
            Log::error('Tarea programada '.$command.': '.$e->getMessage(), ['exception' => $e]);

            return ['ok' => false, 'error' => $e->getMessage()];
        }
    }

    private function save(array $state): void
    {
        @file_put_contents($this->statePath(), json_encode($state, JSON_PRETTY_PRINT), LOCK_EX);
    }
}
