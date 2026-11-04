<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Itinerary;
use App\Models\Trip;
use App\Models\TripCompletion;
use App\Models\ItineraryStop;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Reglas de los viajes (docs/07-algoritmos.md §7.11 a §7.14 y §7.21).
 */
class Trips
{
    /** @var Absences */
    private $absences;

    /** @var ChildEligibility */
    private $childEligibility;

    /** @var Permissions */
    private $permissions;

    public function __construct(Absences $absences, ChildEligibility $childEligibility, Permissions $permissions)
    {
        $this->absences = $absences;
        $this->childEligibility = $childEligibility;
        $this->permissions = $permissions;
    }

    /**
     * Viajes que la persona puede ver (trips.view): los de las Entidades o
     * itinerarios de su ámbito; con «own», los de su itinerario en esa
     * Entidad. Siempre, los que conduce.
     */
    public function visibleTo(User $user): Builder
    {
        $query = Trip::query();
        $scope = $this->permissions->scope($user, 'trips.view');

        if ($scope['all']) {
            return $query;
        }

        $workers = $user->activeWorkers();
        $ownItineraries = $workers->filter(function ($worker) use ($scope) {
            return $worker->itinerary_id && in_array((int) $worker->entity_id, $scope['own'], true);
        })->pluck('itinerary_id')->map(function ($id) {
            return (int) $id;
        })->all();
        $itineraries = array_values(array_unique(array_merge($scope['itineraries'], $ownItineraries)));

        return $query->where(function (Builder $query) use ($scope, $itineraries, $user) {
            $query->whereIn('driver_id', $user->workerIds() ?: [0]);

            if ($scope['entities']) {
                $query->orWhereIn('itinerary_id', Itinerary::withTrashed()->whereIn('entity_id', $scope['entities'])->select('id'));
            }

            if ($itineraries) {
                $query->orWhereIn('itinerary_id', $itineraries);
            }
        });
    }

    /**
     * Es el chofer del viaje (una de sus pertenencias).
     */
    public function isDriverOf(Trip $trip, User $user): bool
    {
        return in_array((int) $trip->driver_id, $user->workerIds(), true);
    }

    public function entityOf(Trip $trip): ?int
    {
        return $this->permissions->entityOfItinerary((int) $trip->itinerary_id);
    }

    /**
     * Comprueba las reglas de un viaje antes de guardarlo: regreso posterior a
     * la salida y, si queda confirmado, que no se solape (7.12).
     */
    public function validate(Trip $trip): void
    {
        if (! $trip->returns_at->greaterThan($trip->departs_at)) {
            throw new JsonApiException(422, 'TRIP_DATES_INVALID', 'Fechas no válidas', 'El regreso debe ser posterior a la salida.', ['pointer' => '/data/attributes/returnsAt']);
        }

        if ($trip->status === Trip::STATUS_CONFIRMED) {
            $this->ensureNoOverlap($trip);
        }
    }

    /**
     * Cambio de estado con sus dos reglas y efectos (7.11). Devuelve el viaje
     * sin guardar los cambios de estado de transición ya aplicados.
     */
    public function applyStatusChange(Trip $trip, string $previousStatus, ?User $user): void
    {
        $status = $trip->status;

        if ($status === $previousStatus) {
            return;
        }

        if ($status === Trip::STATUS_CANCELLED && $previousStatus === Trip::STATUS_COMPLETED) {
            throw $this->transitionNotAllowed('No se puede cancelar un viaje realizado.');
        }

        if ($status === Trip::STATUS_COMPLETED && $previousStatus === Trip::STATUS_CANCELLED) {
            throw $this->transitionNotAllowed('No se puede marcar como realizado un viaje cancelado.');
        }

        if ($previousStatus === Trip::STATUS_COMPLETED) {
            TripCompletion::where('trip_id', $trip->id)->delete();
        }
    }

    /**
     * Efectos que necesitan el viaje ya guardado.
     */
    public function afterStatusChange(Trip $trip, string $previousStatus, ?User $user): void
    {
        if ($trip->status === $previousStatus) {
            return;
        }

        if ($trip->status === Trip::STATUS_COMPLETED && $user) {
            $this->recordCompletion($trip, $user, $this->completionRole($trip, $user));
        }

        if (in_array($trip->status, [Trip::STATUS_CANCELLED, Trip::STATUS_COMPLETED], true)) {
            $this->purgeChat($trip);
        }
    }

    /**
     * Marca el viaje como realizado (7.14). $user null = el sistema.
     */
    public function markCompleted(Trip $trip, ?User $user): TripCompletion
    {
        if ($trip->status === Trip::STATUS_CANCELLED) {
            throw $this->transitionNotAllowed('No se puede marcar como realizado un viaje cancelado.');
        }

        $role = $user ? $this->completionRole($trip, $user) : TripCompletion::ROLE_SYSTEM;

        if ($role === null) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer del viaje y quien tenga permiso para marcar viajes como realizados pueden hacerlo.');
        }

        return DB::transaction(function () use ($trip, $user, $role) {
            $completion = $this->recordCompletion($trip, $user, $role);

            if ($trip->status !== Trip::STATUS_COMPLETED) {
                $previous = $trip->status;
                $trip->status = Trip::STATUS_COMPLETED;
                $trip->save();
                $this->afterStatusChange($trip, $previous, null);
            }

            return $completion;
        });
    }

    /**
     * Rol con el que el usuario puede marcar el viaje como realizado, o null.
     */
    public function completionRole(Trip $trip, User $user): ?string
    {
        if ($user->isAdmin()) {
            return TripCompletion::ROLE_ADMINISTRATOR;
        }

        if ($this->isDriverOf($trip, $user)) {
            return TripCompletion::ROLE_DRIVER;
        }

        if ($this->permissions->can($user, 'trips.complete', null, (int) $trip->itinerary_id)) {
            return TripCompletion::ROLE_MANAGER;
        }

        return null;
    }

    /**
     * Pasajeros esperados (7.13 y docs/11 §11.11): solo trabajadores (ningún
     * niño); los miembros activos del itinerario, sin los que tienen una
     * ausencia en la fecha de salida ni el chofer del viaje.
     *
     * @return Collection|Worker[]
     */
    public function expectedPassengers(Trip $trip): Collection
    {
        $members = Worker::where('itinerary_id', $trip->itinerary_id)
            ->whereHas('user')->with('user')->get();
        $absent = $this->absences->absentOn($trip->departs_at, $members->pluck('id')->all());
        $driverWorkerId = $trip->driver_id ? (int) $trip->driver_id : null;

        return $members->reject(function (Worker $worker) use ($absent, $driverWorkerId) {
            return in_array((int) $worker->id, $absent, true) || (int) $worker->id === $driverWorkerId;
        })->values();
    }

    /**
     * Ocupación (docs/08-version-2.md §8.9). Solo cuentan los trabajadores:
     * no se espera a ningún niño (docs/11 §11.11).
     *
     * - normal: trabajadores ≤ asientos;
     * - saturated (saturado): más que asientos, pero caben de pie;
     * - overloaded (sobresaturado): más que asientos + capacidad de pie.
     */
    public function occupancy(Trip $trip): array
    {
        $passengers = $this->expectedPassengers($trip);
        $vehicle = $trip->vehicle;
        $seats = $vehicle ? (int) $vehicle->seats : 0;
        $capacity = $vehicle ? $vehicle->totalCapacity() : 0;
        $count = $passengers->count();

        return [
            'expectedPassengers' => $count,
            'seats' => $seats,
            'totalCapacity' => $capacity,
            'occupancyLevel' => self::occupancyLevel($count, $seats, $capacity),
            'saturated' => $count > $seats && $count <= $capacity,
            'overloaded' => $count > $capacity,
        ];
    }

    public static function occupancyLevel(int $workers, int $seats, int $capacity): string
    {
        if ($workers > $capacity) {
            return 'overloaded';
        }

        return $workers > $seats ? 'saturated' : 'normal';
    }

    /**
     * Pasajeros esperados por parada (en el orden del itinerario) y, dentro
     * de cada parada, alfabéticamente (docs/08-version-2.md §8.10).
     *
     * @return array lista de [worker, children]
     */
    public function passengerList(Trip $trip, ?int $stopId = null): array
    {
        $passengers = $this->expectedPassengers($trip);

        if ($stopId !== null) {
            $passengers = $passengers->where('stop_id', $stopId)->values();
        }

        $children = $this->childEligibility->eligibleCountsByWorker(
            $passengers->pluck('id')->all(),
            CarbonImmutable::instance($trip->departs_at)
        );
        $positions = ItineraryStop::where('itinerary_id', $trip->itinerary_id)->pluck('position', 'stop_id')->all();

        $list = $passengers->map(function (Worker $worker) use ($children) {
            return ['worker' => $worker, 'children' => isset($children[$worker->id]) ? $children[$worker->id] : 0];
        })->all();

        usort($list, function (array $a, array $b) use ($positions) {
            return $this->listKey($a['worker'], $positions) <=> $this->listKey($b['worker'], $positions);
        });

        return $list;
    }

    private function listKey(Worker $worker, array $positions): array
    {
        $user = $worker->user;

        return [
            isset($positions[$worker->stop_id]) ? (int) $positions[$worker->stop_id] : PHP_INT_MAX,
            $this->collationKey($user ? $user->first_surname : ''),
            $this->collationKey($user ? $user->second_surname : ''),
            $this->collationKey($user ? $user->first_name : ''),
            $this->collationKey($user ? (string) $user->middle_name : ''),
        ];
    }

    /**
     * Clave de orden alfabético en español: sin tildes y con la ñ después de la n.
     */
    private function collationKey(string $value): string
    {
        $value = mb_strtolower($value);
        $value = strtr($value, ['á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => "n\u{FFFF}"]);

        return $value;
    }

    /**
     * Solapamiento con otro viaje confirmado del mismo vehículo o chofer (7.12).
     */
    public function findOverlap(Trip $trip): ?Trip
    {
        return Trip::where('status', Trip::STATUS_CONFIRMED)
            ->when($trip->exists, function (Builder $query) use ($trip) {
                $query->where('id', '!=', $trip->id);
            })
            ->where(function (Builder $query) use ($trip) {
                $query->where('vehicle_id', $trip->vehicle_id)->orWhere('driver_id', $trip->driver_id);
            })
            ->where('departs_at', '<', $trip->returns_at)
            ->where('returns_at', '>', $trip->departs_at)
            ->orderBy('departs_at')
            ->first();
    }

    private function ensureNoOverlap(Trip $trip): void
    {
        $other = $this->findOverlap($trip);

        if ($other) {
            $reason = (int) $other->vehicle_id === (int) $trip->vehicle_id ? 'vehicle' : 'driver';
            $what = $reason === 'vehicle' ? 'El vehículo' : 'El chofer';

            throw JsonApiException::conflict(
                'TRIP_OVERLAP',
                "{$what} ya tiene un viaje confirmado que se solapa (salida ".$other->departs_at->format('d/m/Y H:i').').',
                null,
                ['conflictingTripId' => (string) $other->id, 'reason' => $reason, 'departsAt' => $trip->departs_at->toIso8601String()]
            );
        }
    }

    private function recordCompletion(Trip $trip, ?User $user, string $role): TripCompletion
    {
        $completion = TripCompletion::withTrashed()
            ->where('trip_id', $trip->id)
            ->where('user_id', $user ? $user->id : null)
            ->first();

        if ($completion) {
            if ($completion->trashed()) {
                $completion->restore();
            }

            return $completion;
        }

        return TripCompletion::create(['trip_id' => $trip->id, 'user_id' => $user ? $user->id : null, 'role' => $role]);
    }

    /**
     * El chat del viaje se borra al cancelarse o realizarse, salvo que
     * trip_chat_retention_days lo conserve unos días (lo borra la tarea chats:purge-trips).
     */
    private function purgeChat(Trip $trip): void
    {
        if (app(Settings::class)->int('trip_chat_retention_days', null, null, (int) $trip->itinerary_id) === 0) {
            DB::table('trip_messages')->where('trip_id', $trip->id)->delete();
        }
    }

    private function transitionNotAllowed(string $detail): JsonApiException
    {
        return JsonApiException::conflict('TRIP_TRANSITION_NOT_ALLOWED', $detail, '/data/attributes/status');
    }

    /**
     * Viajes confirmados cuyo regreso (más la demora de su itinerario) ya pasó.
     *
     * @return Collection|Trip[]
     */
    public function dueForAutoCompletion(): Collection
    {
        $settings = app(Settings::class);

        // La demora es un ajuste por itinerario (docs/11 §11.17).
        return Trip::where('status', Trip::STATUS_CONFIRMED)
            ->where('returns_at', '<=', Carbon::now())
            ->get()
            ->filter(function (Trip $trip) use ($settings) {
                $delay = $settings->int('trip_auto_complete_delay_minutes', null, null, (int) $trip->itinerary_id);

                return $trip->returns_at->lessThanOrEqualTo(Carbon::now()->subMinutes($delay));
            })->values();
    }
}
