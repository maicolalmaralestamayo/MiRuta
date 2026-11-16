<?php

namespace App\Services;

use App\Http\Controllers;
use App\Http\Controllers\Nomenclators;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

/**
 * Registro de cambios (docs/11 §11.65): de cada alta, cambio o baja de lo que
 * la app guarda en el teléfono, la tabla, el registro (id), la operación y la
 * fecha y hora. En cada consulta la app pide «qué cambió desde la última vez»
 * (GET sync?changes=N) y recibe solo los registros cambiados (y los ids
 * eliminados), que aplica en el teléfono sin avisar. Se poda pasado el ajuste
 * «Conservación cambios» (1 mes); un teléfono que lleve más tiempo sin
 * conectarse vuelve a descargarlo todo.
 */
class ChangeLog
{
    public const CREATE = 'create';
    public const UPDATE = 'update';
    public const DELETE = 'delete';

    /** Cambios por respuesta (si hay más, la app vuelve a pedir). */
    public const LIMIT = 300;

    /** Tabla => tipo JSON:API (null: solo cambia a sus «padres»). */
    public const TABLES = [
        'entities' => 'entities',
        'itineraries' => 'itineraries',
        'itinerary_stop' => 'itinerary-stops',
        'stops' => 'stops',
        'users' => 'users',
        'workers' => 'workers',
        'worker_itineraries' => 'worker-itineraries',
        'applications' => 'applications',
        'children' => 'children',
        'child_parents' => null,
        'absences' => 'absences',
        'vehicle_types' => 'vehicle-types',
        'absence_types' => 'absence-types',
        'conversation_topics' => 'conversation-topics',
        'entity_denial_reasons' => 'entity-denial-reasons',
        'itinerary_denial_reasons' => 'itinerary-denial-reasons',
        'detention_causes' => 'detention-causes',
        'trips' => 'trips',
        'conversations' => 'conversations',
        'conversation_messages' => 'conversation-messages',
    ];

    /**
     * Lo que se muestra de otros registros y cambia con este (cantidades,
     * nombres…): tabla => [[tabla del «padre», columna con su id]].
     */
    public const PARENTS = [
        'itinerary_stop' => [['itineraries', 'itinerary_id'], ['stops', 'stop_id']],
        'worker_itineraries' => [['itineraries', 'itinerary_id'], ['workers', 'worker_id'], ['users', 'user_id']],
        'workers' => [['users', 'user_id'], ['entities', 'entity_id']],
        'applications' => [['itineraries', 'itinerary_id'], ['entities', 'entity_id']],
        'child_parents' => [['children', 'child_id'], ['users', 'user_id']],
        'absences' => [['users', 'user_id']],
        'conversation_messages' => [['conversations', 'conversation_id']],
    ];

    /**
     * Lo que la base de datos borra (o vacía) al borrar un registro:
     * tabla => [[tabla hija, columna, delete | update]].
     */
    public const CASCADES = [
        'itineraries' => [['itinerary_stop', 'itinerary_id', self::DELETE], ['worker_itineraries', 'itinerary_id', self::DELETE],
            ['trips', 'itinerary_id', self::DELETE], ['applications', 'itinerary_id', self::DELETE]],
        'stops' => [['itinerary_stop', 'stop_id', self::DELETE], ['worker_itineraries', 'stop_id', self::UPDATE], ['applications', 'stop_id', self::UPDATE]],
        'entities' => [['workers', 'entity_id', self::DELETE], ['applications', 'entity_id', self::DELETE], ['itineraries', 'entity_id', self::UPDATE]],
        'users' => [['workers', 'user_id', self::DELETE], ['worker_itineraries', 'user_id', self::DELETE], ['applications', 'user_id', self::DELETE],
            ['child_parents', 'user_id', self::DELETE], ['absences', 'user_id', self::DELETE], ['conversations', 'user_id', self::DELETE]],
        'workers' => [['worker_itineraries', 'worker_id', self::DELETE]],
        'children' => [['child_parents', 'child_id', self::DELETE]],
        'conversations' => [['conversation_messages', 'conversation_id', self::DELETE]],
    ];

    /** Tipo JSON:API => controlador con show() (con él se comprueba que la persona lo ve). */
    public const SHOW = [
        'entities' => Controllers\EntityController::class,
        'itineraries' => Controllers\ItineraryController::class,
        'stops' => Controllers\StopController::class,
        'users' => Controllers\PersonController::class,
        'workers' => Controllers\WorkerController::class,
        'worker-itineraries' => Controllers\WorkerItineraryController::class,
        'applications' => Controllers\ApplicationController::class,
        'children' => Controllers\ChildController::class,
        'absences' => Controllers\AbsenceController::class,
        'vehicle-types' => Nomenclators\VehicleTypeController::class,
        'absence-types' => Nomenclators\AbsenceTypeController::class,
        'conversation-topics' => Nomenclators\ConversationTopicController::class,
        'entity-denial-reasons' => Nomenclators\EntityDenialReasonController::class,
        'itinerary-denial-reasons' => Nomenclators\ItineraryDenialReasonController::class,
        'detention-causes' => Nomenclators\DetentionCauseController::class,
        'trips' => Controllers\TripController::class,
        'conversations' => Controllers\ConversationController::class,
    ];

    private ?bool $ready = null;

    public function __construct(private Settings $settings)
    {
    }

    public function tracks(string $table): bool
    {
        return array_key_exists($table, self::TABLES) && $this->ready();
    }

    /** Hay tabla de registro (antes de «Actualizar base de datos» no la hay). */
    private function ready(): bool
    {
        if ($this->ready === null) {
            try {
                $this->ready = Schema::hasTable('change_log');
            } catch (\Throwable $e) {
                $this->ready = false;
            }
        }

        return $this->ready;
    }

    public function record(string $table, array $ids, string $operation): void
    {
        $ids = array_values(array_unique(array_filter(array_map('intval', $ids))));

        if (! $ids || ! $this->tracks($table)) {
            return;
        }

        $now = Carbon::now();

        foreach (array_chunk($ids, 200) as $chunk) {
            DB::table('change_log')->insert(array_map(fn ($id) => [
                'table_name' => $table, 'record_id' => $id, 'operation' => $operation, 'changed_at' => $now,
            ], $chunk));
        }
    }

    /**
     * Registros dados de alta, cambiados o borrados: ellos y sus «padres».
     *
     * @param Collection $models los modelos (antes del cambio)
     * @param array $values en un cambio en masa, los valores nuevos (para el «padre» nuevo)
     */
    public function modelsChanged(string $table, Collection $models, string $operation, array $values = []): void
    {
        if ($models->isEmpty() || ! $this->tracks($table)) {
            return;
        }

        $this->record($table, $models->map(fn ($m) => $m->getKey())->all(), $operation);

        foreach (self::PARENTS[$table] ?? [] as [$parent, $column]) {
            $ids = $models->map(fn ($m) => $m->getAttribute($column))->all();

            if (array_key_exists($column, $values)) {
                $ids[] = $values[$column];
            }

            // Antes de un save() el modelo ya tiene el valor nuevo; el viejo, en getOriginal().
            foreach ($models as $model) {
                $ids[] = $model->getOriginal($column);
            }

            $this->record($parent, array_filter($ids), self::UPDATE);
        }
    }

    /**
     * Antes de borrar: lo que la base de datos borrará o vaciará en cascada.
     */
    public function cascade(string $table, array $ids, int $depth = 0): void
    {
        if (! $ids || $depth > 2) {
            return;
        }

        foreach (self::CASCADES[$table] ?? [] as [$child, $column, $operation]) {
            if (! Schema::hasTable($child)) {
                continue;
            }

            $rows = DB::table($child)->whereIn($column, $ids)->get();

            if ($rows->isEmpty()) {
                continue;
            }

            $childIds = $rows->pluck('id')->all();

            if ($operation === self::DELETE) {
                $this->cascade($child, $childIds, $depth + 1);
            }

            $this->record($child, $childIds, $operation);

            foreach (self::PARENTS[$child] ?? [] as [$parent, $parentColumn]) {
                if ($parent !== $table) {
                    $this->record($parent, $rows->pluck($parentColumn)->filter()->all(), self::UPDATE);
                }
            }
        }
    }

    /** Cursor actual (último cambio registrado). */
    public function cursor(): int
    {
        return $this->ready() ? (int) DB::table('change_log')->max('id') : 0;
    }

    /**
     * Qué cambió desde $cursor para esa persona: los registros que ve
     * (serializados como en GET tipo/id) y los ids que ya no ve o se borraron.
     * full = true si el teléfono debe volver a descargarlo todo (sin cursor, o
     * más viejo que lo que conserva el registro).
     *
     * @return array{cursor: string, full: bool, more: bool, data: array, deleted: array<string, string[]>, changed: string[]}
     */
    public function since(Request $request, $cursor): array
    {
        $current = $this->cursor();
        $empty = ['cursor' => (string) $current, 'full' => false, 'more' => false, 'data' => [], 'deleted' => (object) [], 'changed' => []];

        if ($cursor === null || $cursor === '' || ! ctype_digit((string) $cursor) || ! $this->ready()) {
            return ['full' => true] + $empty;
        }

        $cursor = (int) $cursor;
        $oldest = (int) DB::table('change_log')->min('id');

        if ($cursor > $current || ($oldest > 0 && $cursor < $oldest - 1)) {
            return ['full' => true] + $empty;
        }

        $rows = DB::table('change_log')->where('id', '>', $cursor)->orderBy('id')->limit(self::LIMIT + 1)->get();
        $more = $rows->count() > self::LIMIT;
        $rows = $rows->take(self::LIMIT);
        $next = $rows->isEmpty() ? $cursor : (int) $rows->last()->id;

        // El último cambio de cada registro.
        $last = [];

        foreach ($rows as $row) {
            $type = self::TABLES[$row->table_name] ?? null;

            if ($type !== null) {
                $last[$type][(int) $row->record_id] = $row->operation;
            }
        }

        $data = [];
        $deleted = [];

        foreach ($last as $type => $records) {
            foreach ($records as $id => $operation) {
                $resource = $operation === self::DELETE ? null : $this->show($request, $type, $id);

                if ($resource === false) {
                    // Sin forma de consultarlo uno a uno: la app vuelve a pedir sus listas.
                    continue;
                }

                if ($resource === null) {
                    $deleted[$type][] = (string) $id;
                } else {
                    $data[] = $resource;
                }
            }
        }

        return [
            'cursor' => (string) $next,
            'full' => false,
            'more' => $more,
            'data' => $data,
            'deleted' => (object) $deleted,
            // Tipos con cambios (para las listas que la app vuelve a pedir).
            'changed' => array_keys($last),
        ];
    }

    /**
     * El registro como lo devuelve GET tipo/id para esa persona; null si no lo
     * ve (o ya no existe) y false si ese tipo no se consulta uno a uno.
     */
    private function show(Request $request, string $type, int $id): array|null|false
    {
        $controller = self::SHOW[$type] ?? null;

        if ($controller === null) {
            return false;
        }

        $sub = Request::create('/api/v1/'.$type.'/'.$id, 'GET', [], [], [], $request->server->all());
        $sub->setUserResolver($request->getUserResolver());

        try {
            $response = app($controller)->show($sub, $id);
            $document = $response->getData(true);

            return $document['data'] ?? null;
        } catch (HttpExceptionInterface|\Illuminate\Database\Eloquent\ModelNotFoundException|\Illuminate\Auth\Access\AuthorizationException $e) {
            return null;
        } catch (\App\JsonApi\JsonApiException $e) {
            return null;
        }
    }

    /**
     * Poda (tarea diaria): borra lo más viejo que «Conservación cambios»,
     * pero siempre deja el último (para saber desde dónde falta).
     */
    public function prune(): int
    {
        if (! $this->ready()) {
            return 0;
        }

        $last = (int) DB::table('change_log')->max('id');

        return DB::table('change_log')->where('changed_at', '<', Carbon::now()->subSeconds($this->settings->seconds('conservacion_cambios')))
            ->where('id', '<', $last)->delete();
    }
}
