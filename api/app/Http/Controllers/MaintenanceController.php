<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\ScheduledTasks;
use App\Services\Uploads;
use Carbon\Carbon;
use Illuminate\Contracts\Console\Kernel as ConsoleKernel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Str;

/**
 * Mantenimiento del servidor desde la app, para hospedajes sin SSH (docs/11 §11.55): ver el
 * estado, instalar o actualizar la base de datos, ejecutar las tareas
 * programadas, limpiar la caché y leer el registro de errores.
 *
 * Solo se ejecutan las órdenes de esta lista; nunca una orden libre.
 */
class MaintenanceController extends Controller
{
    public const COMMANDS = ['install', 'migrate', 'run-tasks', 'clear-cache', 'log'];

    public const EXTENSIONS = ['pdo_mysql', 'mbstring', 'openssl', 'fileinfo', 'tokenizer', 'ctype', 'xml', 'dom', 'zip'];

    public function status(ScheduledTasks $tasks, Uploads $uploads)
    {
        $database = $this->databaseStatus();

        return JsonApiResponse::make(['data' => [
            'type' => 'server-statuses',
            'id' => 'current',
            'attributes' => [
                'apiVersion' => config('miruta.version'),
                'phpVersion' => PHP_VERSION,
                'phpSupported' => version_compare(PHP_VERSION, '8.2.0', '>='),
                'extensions' => array_combine(self::EXTENSIONS, array_map('extension_loaded', self::EXTENSIONS)),
                'php' => [
                    'uploadMaxFilesize' => ini_get('upload_max_filesize'),
                    'postMaxSize' => ini_get('post_max_size'),
                    'memoryLimit' => ini_get('memory_limit'),
                    'maxExecutionTime' => ini_get('max_execution_time'),
                    'openBasedir' => ini_get('open_basedir') ?: null,
                    'tempDir' => sys_get_temp_dir(),
                ],
                'serverTime' => Carbon::now()->toIso8601String(),
                'timezone' => date_default_timezone_get(),
                'database' => $database,
                'storage' => $this->folderStatus(storage_path()),
                'uploads' => $this->folderStatus($uploads->publicPath(config('miruta.uploads_directory'))),
                'tasks' => [
                    'onRequests' => (bool) config('miruta.tasks_on_requests'),
                    'lastCheck' => $tasks->state()['_lastCheck'] ?? null,
                    'list' => $this->taskList($tasks),
                ],
                'commands' => self::COMMANDS,
            ],
        ]]);
    }

    public function run(Request $request, ScheduledTasks $tasks)
    {
        $command = $request->input('data.attributes.command');

        if (! in_array($command, self::COMMANDS, true)) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Orden desconocida',
                'Las órdenes posibles son: '.implode(', ', self::COMMANDS).'.', ['pointer' => '/data/attributes/command']);
        }

        @set_time_limit(600);
        $ok = true;

        try {
            switch ($command) {
                case 'install':
                    if ($this->databaseStatus()['installed']) {
                        throw new JsonApiException(409, 'ALREADY_INSTALLED', 'Ya está instalada',
                            'La base de datos ya está instalada. Para aplicar cambios de una versión nueva use «Actualizar base de datos».');
                    }
                    $output = $this->artisan('migrate', ['--force' => true])
                        .$this->artisan('db:seed', ['--force' => true]);
                    break;

                case 'migrate':
                    $output = $this->artisan('migrate', ['--force' => true]);
                    break;

                case 'run-tasks':
                    $results = $tasks->runDue();
                    $lines = [];
                    foreach ($results as $name => $result) {
                        $ok = $ok && $result['ok'];
                        $lines[] = $name.': '.($result['ok'] ? 'bien' : 'error: '.$result['error']);
                    }
                    $output = $lines ? implode("\n", $lines) : 'No había tareas pendientes.';
                    break;

                case 'clear-cache':
                    $output = $this->artisan('optimize:clear');
                    break;

                case 'log':
                    $output = $this->logTail(200);
                    break;
            }
        } catch (JsonApiException $e) {
            throw $e;
        } catch (\Throwable $e) {
            report($e);
            $ok = false;
            $output = ($output ?? '').get_class($e).': '.$e->getMessage();
        }

        return JsonApiResponse::make(['data' => [
            'type' => 'maintenance-runs',
            'id' => (string) Str::uuid(),
            'attributes' => [
                'command' => $command,
                'ok' => $ok,
                'output' => trim((string) $output),
                'ranAt' => Carbon::now()->toIso8601String(),
            ],
        ]], 201);
    }

    private function artisan(string $command, array $parameters = []): string
    {
        app(ConsoleKernel::class);
        $code = Artisan::call($command, $parameters);
        $output = Artisan::output();

        if ($code !== 0) {
            throw new \RuntimeException(trim($output) ?: "La orden {$command} terminó con el código {$code}.");
        }

        return $output;
    }

    private function databaseStatus(): array
    {
        $status = ['connected' => false, 'error' => null, 'installed' => false, 'pendingMigrations' => []];

        try {
            DB::connection()->getPdo();
            $status['connected'] = true;
            $status['installed'] = Schema::hasTable('migrations') && Schema::hasTable('users');

            app(ConsoleKernel::class);
            $migrator = app('migrator');
            $files = array_keys($migrator->getMigrationFiles(database_path('migrations')));
            $ran = $migrator->repositoryExists() ? $migrator->getRepository()->getRan() : [];
            $status['pendingMigrations'] = array_values(array_diff($files, $ran));
        } catch (\Throwable $e) {
            $status['error'] = $e->getMessage();
        }

        return $status;
    }

    private function folderStatus(string $path): array
    {
        return ['path' => $path, 'exists' => is_dir($path), 'writable' => is_dir($path) && is_writable($path)];
    }

    private function taskList(ScheduledTasks $tasks): array
    {
        $state = $tasks->state();
        $list = [];

        foreach (ScheduledTasks::TASKS as $command => [$frequency]) {
            $list[] = [
                'command' => $command,
                'frequency' => $frequency,
                'lastRun' => $state[$command]['lastAttempt'] ?? $state[$command]['lastRun'] ?? null,
                'ok' => $state[$command]['ok'] ?? null,
                'error' => $state[$command]['error'] ?? null,
            ];
        }

        return $list;
    }

    private function logTail(int $lines): string
    {
        $files = glob(storage_path('logs/*.log')) ?: [];

        if (! $files) {
            return 'No hay errores registrados.';
        }

        usort($files, function ($a, $b) {
            return filemtime($b) <=> filemtime($a);
        });

        $content = (string) file_get_contents($files[0], false, null, max(0, filesize($files[0]) - 200000));
        $tail = array_slice(preg_split('/\R/', rtrim($content)), -$lines);

        return basename($files[0])."\n\n".implode("\n", $tail);
    }
}
