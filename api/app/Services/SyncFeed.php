<?php

namespace App\Services;

use App\Http\Controllers\TripController;
use App\Http\Middleware\RequireCurrentAppVersion;
use App\JsonApi\JsonApiException;
use App\Models\AppVersion;
use App\Models\Itinerary;
use App\Models\Notification;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

/**
 * Lo que la app recibe en cada consulta (docs/11 §11.44, §11.47 y §11.62):
 * notificaciones nuevas desde el cursor y un meta pequeño. Lo usan
 * GET sync (fuera de la ventana de viaje, cada «Frecuencia fuera ventana») y
 * POST trips/{id}/reports?cursor=N (dentro de la ventana, cada «Frecuencia
 * ventana», en la misma petición en que el teléfono envía sus cambios).
 *
 * - meta.myTrips: los viajes en que la persona es pasajero esperado (de ayer a
 *   7 días, y los cerrados en el último día) para su ventana de viaje.
 * - meta.finishedTrips: viajes que terminaron (la app quita sus notificaciones).
 * - meta.pendingApplications: solicitudes pendientes que le toca resolver, por tipo.
 * - meta.versions: huella de cada grupo de datos (Entidades, itinerarios…)
 *   para las apps 4.2.0 y 4.3.0: si cambia, vuelven a pedir esos datos.
 * - meta.changes (4.4.0, con ?changes=N): registro de cambios desde N
 *   (App\Services\ChangeLog): los registros cambiados que ve la persona, los
 *   ids borrados y si debe volver a descargarlo todo (full).
 */
class SyncFeed
{
    public const LIMIT = 100;

    /** Grupos de datos de meta.versions => tablas (con updated_at) y tablas sin él. */
    public const VERSION_TABLES = [
        'entities' => [['entities'], []],
        'itineraries' => [['itineraries', 'itinerary_stop'], []],
        'stops' => [['stops'], []],
        'workers' => [['users', 'workers', 'worker_itineraries'], []],
        'applications' => [['applications'], []],
        'children' => [['children', 'child_parents'], []],
        'absences' => [['absences'], ['absence_itinerary']],
        'nomenclators' => [['vehicle_types', 'absence_types', 'conversation_topics', 'entity_denial_reasons', 'itinerary_denial_reasons', 'detention_causes'], []],
        'trips' => [['trips'], []],
        'conversations' => [['conversations', 'conversation_messages'], []],
    ];

    public function __construct(private Applications $applications, private Conversations $conversations, private Settings $settings, private Trips $trips, private ChangeLog $changeLog)
    {
    }

    /**
     * @return array{0: array, 1: array} [data, meta]
     */
    public function build(User $user, $cursor, Request $request): array
    {
        if ($cursor !== null && ! ctype_digit((string) $cursor)) {
            throw JsonApiException::badRequest('cursor debe ser un número entero.', 'cursor');
        }

        $data = [];
        $changed = [];

        if ($cursor === null) {
            $next = (int) Notification::where('user_id', $user->id)->max('id');
            $more = false;
        } else {
            $items = Notification::where('user_id', $user->id)->where('id', '>', (int) $cursor)->orderBy('id')->limit(self::LIMIT + 1)->get();
            $more = $items->count() > self::LIMIT;
            $items = $items->take(self::LIMIT);
            $next = $items->isEmpty() ? (int) $cursor : (int) $items->last()->id;

            foreach ($items as $item) {
                $data[] = [
                    'type' => 'notifications',
                    'id' => (string) $item->id,
                    'attributes' => [
                        'kind' => $item->kind,
                        'title' => $item->title,
                        'body' => $item->body,
                        'data' => (object) $item->dataArray(),
                        'createdAt' => $item->created_at->toIso8601String(),
                    ],
                ];
                $changed[Notifier::CHANGES[$item->kind] ?? 'other'] = true;
            }
        }

        $installed = RequireCurrentAppVersion::versionCode($request);
        $latest = AppVersion::latest();
        $nextTrip = $this->trips->visibleQuery($user)->whereIn('status', [Trip::PLANNED, Trip::RUNNING])
            ->where('date', '>=', Carbon::today()->toDateString())
            ->orderByRaw("case when status = 'en_ejecucion' then 0 else 1 end")->orderBy('departs_at')->first();

        $meta = [
            'cursor' => (string) $next,
            'more' => $more,
            'changed' => array_keys($changed),
            'counters' => [
                'applicationsToResolve' => $this->applications->pendingToResolve($user),
                'applicationsResolvedUnseen' => $this->applications->unseenResolved($user),
                'conversationsUnread' => $this->conversations->unreadCount($user),
            ],
            'latestAppVersion' => $latest ? [
                'id' => (string) $latest->id,
                'versionCode' => $latest->version_code,
                'versionName' => $latest->version_name,
                'updateAvailable' => $installed !== null && $latest->version_code > $installed,
                'mandatory' => $installed !== null && AppVersion::isMandatoryAfter($installed),
            ] : null,
            'nextTrip' => $nextTrip ? [
                'id' => (string) $nextTrip->id,
                'direction' => $nextTrip->direction,
                'status' => $nextTrip->status,
                'departsAt' => $nextTrip->departs_at->toIso8601String(),
                'today' => $nextTrip->date->isToday(),
                'itineraryId' => (string) $nextTrip->itinerary_id,
            ] : null,
            'myTrips' => $this->myTrips($user, $request),
            'finishedTrips' => $this->finishedTrips($user),
            // Por tipo, para la notificación «N solicitudes pendientes» (docs/11 §11.63).
            'pendingApplications' => $this->applications->pendingByType($user),
            // Huellas de la 4.2.0 / 4.3.0 (las apps 4.4.0 usan meta.changes).
            'versions' => $this->versions(),
            'settingsVersion' => $this->settings->version(),
            'serverTime' => Carbon::now()->toIso8601String(),
        ];

        // Registro de cambios (docs/11 §11.65): con ?changes=N, lo que cambió desde N.
        if ($request->query->has('changes')) {
            $meta['changes'] = $this->changeLog->since($request, $request->query('changes'));
        }

        return [$data, $meta];
    }

    /**
     * Viajes en que la persona viaja (pasajero esperado o ya informó su
     * estado): la base de su ventana de viaje (docs/11 §11.62).
     */
    public function myTrips(User $user, ?Request $request = null): array
    {
        // Parada habitual opcional (docs/11 §11.65): cuenta cualquier itinerario suyo.
        $itineraryIds = DB::table('worker_itineraries')->where('user_id', $user->id)->pluck('itinerary_id')->all();

        if (! $itineraryIds) {
            return [];
        }

        $now = Carbon::now();
        $trips = Trip::whereIn('itinerary_id', $itineraryIds)
            ->where('date', '>=', Carbon::yesterday()->toDateString())
            ->where('date', '<=', Carbon::today()->addDays(7)->toDateString())
            ->where(fn ($q) => $q->whereIn('status', [Trip::PLANNED, Trip::RUNNING])
                ->orWhere('status_changed_at', '>=', $now->copy()->subDay()))
            ->orderBy('departs_at')->limit(20)->get();
        $names = Itinerary::whereIn('id', $trips->pluck('itinerary_id')->unique()->all() ?: [0])->pluck('name', 'id');
        $states = TripPassenger::whereIn('trip_id', $trips->pluck('id')->all() ?: [0])->where('user_id', $user->id)->get()->keyBy('trip_id');
        $result = [];

        foreach ($trips as $trip) {
            $state = $states[$trip->id] ?? null;
            $expected = $this->trips->expectedQuery($trip)->where('user_id', $user->id)->first();

            if (! $expected && ! $state) {
                continue;
            }

            $result[] = [
                'id' => (string) $trip->id,
                'itineraryId' => (string) $trip->itinerary_id,
                'itineraryName' => $names[$trip->itinerary_id] ?? null,
                'direction' => $trip->direction,
                'status' => $trip->status,
                'departsAt' => $trip->departs_at->toIso8601String(),
                'statusChangedAt' => $trip->status_changed_at?->toIso8601String(),
                'myStopId' => ($expected?->stop_id ?? $state?->stop_id) ? (string) ($expected?->stop_id ?? $state?->stop_id) : null,
                // Viaja en él (aunque no tenga parada habitual).
                'travels' => true,
                'myState' => $request ? TripController::legacyState($request, $trip, $state?->state) : $state?->state,
                'myStateAt' => $state?->state_at?->toIso8601String(),
            ];
        }

        return $result;
    }

    /**
     * Viajes que ve y que terminaron en los últimos dos días: la app quita
     * sus notificaciones del viaje y del vehículo (docs/11 §11.63).
     *
     * @return string[]
     */
    public function finishedTrips(User $user): array
    {
        return $this->trips->visibleQuery($user)->where('status', Trip::FINISHED)
            ->where('status_changed_at', '>=', Carbon::now()->subDays(2))
            ->orderByDesc('status_changed_at')->limit(50)->pluck('id')->map(fn ($id) => (string) $id)->all();
    }

    /**
     * Huella de cada grupo de datos (cantidad y última modificación), guardada
     * unos segundos para no repetir las consultas en cada teléfono.
     *
     * @return array<string, string>
     */
    public function versions(): array
    {
        return Cache::remember('sync.versions', 10, function () {
            $versions = [];

            foreach (self::VERSION_TABLES as $group => [$withDates, $withoutDates]) {
                $parts = [];

                foreach ($withDates as $table) {
                    $row = DB::table($table)->selectRaw('count(*) as c, max(updated_at) as u')->first();
                    $parts[] = $row->c.'@'.$row->u;
                }

                foreach ($withoutDates as $table) {
                    $parts[] = (string) DB::table($table)->count();
                }

                $versions[$group] = substr(md5(implode('|', $parts)), 0, 12);
            }

            $versions['settings'] = substr(md5((string) $this->settings->version()), 0, 12);

            return $versions;
        });
    }
}
