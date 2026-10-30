<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Trip;
use App\Models\TripCompletion;
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

    public function __construct(Absences $absences, ChildEligibility $childEligibility)
    {
        $this->absences = $absences;
        $this->childEligibility = $childEligibility;
    }

    /**
     * Viajes que el usuario puede ver.
     */
    public function visibleTo(Worker $user): Builder
    {
        $query = Trip::query();

        if ($user->managesTransport()) {
            return $query;
        }

        return $query->where(function (Builder $query) use ($user) {
            $query->whereRaw('1 = 0');

            if ($user->itinerary_id) {
                $query->orWhere('itinerary_id', $user->itinerary_id);
            }

            if ($chiefOf = $user->chiefItineraryIds()) {
                $query->orWhereIn('itinerary_id', $chiefOf);
            }

            if ($driverId = $user->driverId()) {
                $query->orWhere('driver_id', $driverId);
            }
        });
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
    public function applyStatusChange(Trip $trip, string $previousStatus, ?Worker $user): void
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
    public function afterStatusChange(Trip $trip, string $previousStatus, ?Worker $user): void
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
    public function markCompleted(Trip $trip, ?Worker $user): TripCompletion
    {
        if ($trip->status === Trip::STATUS_CANCELLED) {
            throw $this->transitionNotAllowed('No se puede marcar como realizado un viaje cancelado.');
        }

        $role = $user ? $this->completionRole($trip, $user) : TripCompletion::ROLE_SYSTEM;

        if ($role === null) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer del viaje, los Jefes de su itinerario y los Jefes de Transporte pueden marcarlo como realizado.');
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
    public function completionRole(Trip $trip, Worker $user): ?string
    {
        if ($user->isAdmin()) {
            return TripCompletion::ROLE_ADMINISTRATOR;
        }

        if ($user->isTransportChief()) {
            return TripCompletion::ROLE_TRANSPORT_CHIEF;
        }

        if ($user->driverId() !== null && (int) $trip->driver_id === $user->driverId()) {
            return TripCompletion::ROLE_DRIVER;
        }

        if ($user->isChiefOf((int) $trip->itinerary_id)) {
            return TripCompletion::ROLE_ITINERARY_CHIEF;
        }

        return null;
    }

    /**
     * Pasajeros esperados (7.13): miembros activos del itinerario, sin los que
     * tienen ausencia aprobada en la fecha de salida ni el chofer del viaje.
     *
     * @return Collection|Worker[]
     */
    public function expectedPassengers(Trip $trip): Collection
    {
        $members = Worker::where('itinerary_id', $trip->itinerary_id)->with('rank')->get();
        $absent = $this->absences->absentOn($trip->departs_at, $members->pluck('id')->all());
        $driverWorkerId = $trip->driver ? (int) $trip->driver->worker_id : null;

        return $members->reject(function (Worker $worker) use ($absent, $driverWorkerId) {
            return in_array((int) $worker->id, $absent, true) || (int) $worker->id === $driverWorkerId;
        })->values();
    }

    /**
     * @return array [esperados, niños esperados, capacidad, sobresaturado]
     */
    public function occupancy(Trip $trip): array
    {
        $passengers = $this->expectedPassengers($trip);
        $children = array_sum($this->childEligibility->eligibleCountsByWorker(
            $passengers->pluck('id')->all(),
            CarbonImmutable::instance($trip->departs_at)
        ));
        $capacity = $trip->vehicle ? $trip->vehicle->totalCapacity() : 0;

        return [
            'expectedPassengers' => $passengers->count(),
            'expectedChildren' => $children,
            'totalCapacity' => $capacity,
            'overloaded' => $passengers->count() > $capacity,
        ];
    }

    /**
     * Pasajeros en orden de subida (7.21): primero los que suben con niños;
     * después mujeres y luego hombres; dentro de cada grupo, por jerarquía y
     * alfabéticamente.
     *
     * @return array lista de [worker, children, order]
     */
    public function boardingOrder(Trip $trip, ?int $stopId = null): array
    {
        $passengers = $this->expectedPassengers($trip);

        if ($stopId !== null) {
            $passengers = $passengers->where('stop_id', $stopId)->values();
        }

        $children = $this->childEligibility->eligibleCountsByWorker(
            $passengers->pluck('id')->all(),
            CarbonImmutable::instance($trip->departs_at)
        );

        $list = $passengers->map(function (Worker $worker) use ($children) {
            return ['worker' => $worker, 'children' => $children[$worker->id]];
        })->all();

        usort($list, function (array $a, array $b) {
            return $this->boardingKey($a) <=> $this->boardingKey($b);
        });

        foreach ($list as $index => &$item) {
            $item['order'] = $index + 1;
        }

        return $list;
    }

    private function boardingKey(array $item): array
    {
        $worker = $item['worker'];

        return [
            $item['children'] > 0 ? 0 : 1,
            $worker->sex === Worker::SEX_FEMALE ? 0 : 1,
            $worker->rank ? $worker->rank->precedence : PHP_INT_MAX,
            $this->collationKey($worker->last_name),
            $this->collationKey($worker->first_name),
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

    private function recordCompletion(Trip $trip, ?Worker $user, string $role): TripCompletion
    {
        $completion = TripCompletion::withTrashed()
            ->where('trip_id', $trip->id)
            ->where('worker_id', $user ? $user->id : null)
            ->first();

        if ($completion) {
            if ($completion->trashed()) {
                $completion->restore();
            }

            return $completion;
        }

        return TripCompletion::create(['trip_id' => $trip->id, 'worker_id' => $user ? $user->id : null, 'role' => $role]);
    }

    /**
     * El chat del viaje se borra al cancelarse o realizarse.
     */
    private function purgeChat(Trip $trip): void
    {
        DB::table('trip_messages')->where('trip_id', $trip->id)->delete();
    }

    private function transitionNotAllowed(string $detail): JsonApiException
    {
        return JsonApiException::conflict('TRIP_TRANSITION_NOT_ALLOWED', $detail, '/data/attributes/status');
    }

    /**
     * Viajes confirmados cuyo regreso (más la demora configurada) ya pasó.
     *
     * @return Collection|Trip[]
     */
    public function dueForAutoCompletion(int $delayMinutes): Collection
    {
        return Trip::where('status', Trip::STATUS_CONFIRMED)
            ->where('returns_at', '<=', Carbon::now()->subMinutes($delayMinutes))
            ->get();
    }
}
