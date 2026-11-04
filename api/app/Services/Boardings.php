<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Child;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripBoardingChild;
use App\Models\TripLeg;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * Registro de subida (docs/07-algoritmos.md §7.22 y docs/11 §11.8, §11.9 y §11.11):
 *
 * - una sola subida por persona y trayecto;
 * - al subir se marcan qué hijos suben; cada niño cuenta una vez por trayecto;
 * - alguien de otro itinerario o de otra Entidad sube solo si quien escanea
 *   tiene tracking.allow_outsiders y lo confirma (se registra `outsider`).
 */
class Boardings
{
    /** Margen al sincronizar escaneos hechos sin conexión cerca del inicio o del fin del trayecto. */
    const LEG_MARGIN_SECONDS = 120;

    /** @var ChildEligibility */
    private $childEligibility;

    /** @var Permissions */
    private $permissions;

    public function __construct(ChildEligibility $childEligibility, Permissions $permissions)
    {
        $this->childEligibility = $childEligibility;
        $this->permissions = $permissions;
    }

    /**
     * Pertenencia con la que viaja la persona y si es de fuera:
     * [Worker, null | 'itinerary' | 'entity'].
     */
    public function passengerOf(Trip $trip, User $user): array
    {
        $entityId = $this->permissions->entityOfItinerary((int) $trip->itinerary_id);
        $worker = Worker::where('user_id', $user->id)->where('entity_id', $entityId)->first();

        if ($worker) {
            return [$worker, (int) $worker->itinerary_id === (int) $trip->itinerary_id ? null : TripBoarding::OUTSIDER_ITINERARY];
        }

        $other = Worker::where('user_id', $user->id)->orderBy('id')->first();

        if (! $other) {
            throw new JsonApiException(422, 'NOT_A_WORKER', 'Sin Entidad',
                'Esta persona no pertenece a ninguna Entidad: no puede subir al transporte.', ['pointer' => '/data/attributes/qr']);
        }

        return [$other, TripBoarding::OUTSIDER_ENTITY];
    }

    /**
     * Subida existente de la persona en el trayecto (con cualquiera de sus pertenencias).
     */
    public function existingFor(TripLeg $leg, int $userId): ?TripBoarding
    {
        return TripBoarding::where('trip_leg_id', $leg->id)
            ->whereIn('worker_id', Worker::withTrashed()->where('user_id', $userId)->select('id'))
            ->orderBy('id')->first();
    }

    /**
     * Puede dejar subir a gente de fuera en ese viaje.
     */
    public function canAllowOutsiders(Trip $trip, User $user): bool
    {
        return $this->permissions->can($user, 'tracking.allow_outsiders', null, (int) $trip->itinerary_id);
    }

    public function canFixPassengers(Trip $trip, User $user): bool
    {
        return $this->permissions->can($user, 'tracking.fix_passengers', null, (int) $trip->itinerary_id);
    }

    /**
     * El trayecto admite subidas a esa hora: en curso o, al sincronizar, la
     * hora del escaneo cae dentro del trayecto. Quien corrige los pasajeros
     * (tracking.fix_passengers) puede hacerlo después.
     */
    public function ensureLegOpen(TripLeg $leg, ?CarbonInterface $at, ?User $by): void
    {
        if ($leg->isActive()) {
            return;
        }

        if ($at !== null && $leg->ended_at
            && $at->getTimestamp() >= $leg->started_at->getTimestamp() - self::LEG_MARGIN_SECONDS
            && $at->getTimestamp() <= $leg->ended_at->getTimestamp() + self::LEG_MARGIN_SECONDS) {
            return;
        }

        if ($by && $this->canFixPassengers($leg->trip, $by)) {
            return;
        }

        throw JsonApiException::conflict('LEG_NOT_ACTIVE', 'El trayecto no está en curso.');
    }

    /**
     * Registra la subida de la persona.
     *
     * @param array $options childIds (int[]|null: null = sin cambiar / ninguno),
     *                       allowOutsider (bool), at (hora del escaneo), qrKind, scanner (User|null)
     * @return array ['boarding' => TripBoarding, 'created' => bool]
     */
    public function register(TripLeg $leg, User $person, string $method, array $options = []): array
    {
        $trip = $leg->trip;
        $scanner = isset($options['scanner']) ? $options['scanner'] : null;
        $at = isset($options['at']) ? Carbon::instance($options['at']) : Carbon::now();
        $childIds = array_key_exists('childIds', $options) ? $options['childIds'] : null;
        $qrKind = isset($options['qrKind']) ? $options['qrKind'] : null;
        $isScan = in_array($method, [TripBoarding::METHOD_QR, TripBoarding::METHOD_MANUAL], true);

        if ($method !== TripBoarding::METHOD_AUTOMATIC) {
            $this->ensureLegOpen($leg, isset($options['at']) ? $at : null, $scanner);
        }

        list($worker, $outsider) = $this->passengerOf($trip, $person);

        if ($outsider !== null) {
            if (! $isScan) {
                throw new JsonApiException(422, 'NOT_A_PASSENGER', 'No es pasajero', 'No es miembro del itinerario de este viaje.');
            }

            if (! $scanner || ! $this->canAllowOutsiders($trip, $scanner)) {
                throw new JsonApiException(403, 'OUTSIDER_NOT_ALLOWED', 'Sin permiso', $this->outsiderText($outsider)
                    .' No tiene permiso para dejar subir a personas de otro itinerario o Entidad.', [], ['outsider' => $outsider]);
            }

            if (empty($options['allowOutsider'])) {
                throw JsonApiException::conflict('OUTSIDER_CONFIRMATION_REQUIRED', $this->outsiderText($outsider)
                    .' Confirme si la deja subir (allowOutsider).', '/data/attributes/allowOutsider', ['outsider' => $outsider]);
            }
        }

        return DB::transaction(function () use ($leg, $trip, $person, $worker, $outsider, $method, $scanner, $at, $childIds, $qrKind, $isScan, $options) {
            $boarding = $this->existingFor($leg, (int) $person->id);
            $created = false;

            if ($boarding) {
                $scanned = in_array($boarding->method, [TripBoarding::METHOD_QR, TripBoarding::METHOD_MANUAL], true);

                if ($isScan && $scanned) {
                    throw JsonApiException::conflict('ALREADY_BOARDED', $this->alreadyBoardedText($boarding, $qrKind), null, [
                        'boardingId' => (string) $boarding->id, 'qrKind' => $boarding->qr_kind,
                    ]);
                }

                if ($method === TripBoarding::METHOD_AUTOMATIC) {
                    return ['boarding' => $boarding, 'created' => false];
                }

                if ($isScan) {
                    // Pasa de automática o "Ya subí" a escaneada.
                    $boarding->forceFill([
                        'method' => $method, 'marked_by' => $scanner ? $scanner->id : null, 'qr_kind' => $qrKind,
                        'worker_id' => $worker->id, 'outsider' => $outsider,
                    ])->save();
                }
            } else {
                $boarding = TripBoarding::create([
                    'trip_leg_id' => $leg->id,
                    'worker_id' => $worker->id,
                    'method' => $method,
                    'marked_by' => $scanner ? $scanner->id : ($method === TripBoarding::METHOD_SELF ? $person->id : null),
                    'children_count' => 0,
                    'outsider' => $outsider,
                    'qr_kind' => $qrKind,
                    'boarded_at' => $at,
                ]);
                $created = true;
            }

            if ($childIds !== null) {
                $this->setChildren($boarding, $person, $childIds);
            }

            if (isset($options['afterSave'])) {
                $options['afterSave']($boarding);
            }

            return ['boarding' => $boarding->fresh(), 'created' => $created];
        });
    }

    /**
     * Marca qué hijos suben con la persona (sustituye a los anteriores).
     *
     * @param int[] $childIds
     */
    public function setChildren(TripBoarding $boarding, User $person, array $childIds, string $pointer = '/data/attributes/childIds'): void
    {
        $childIds = array_values(array_unique(array_map('intval', $childIds)));
        $leg = $boarding->tripLeg;
        $date = CarbonImmutable::instance($leg->trip->departs_at);
        $eligible = $this->childEligibility->eligibleChildrenOf((int) $person->id, $date)->keyBy('id');

        foreach ($childIds as $childId) {
            if (! $eligible->has($childId)) {
                throw new JsonApiException(422, 'CHILD_NOT_ELIGIBLE', 'Hijo no válido',
                    'Solo pueden subir con la persona sus hijos activos con derecho a viajar.', ['pointer' => $pointer]);
            }
        }

        $taken = TripBoardingChild::where('trip_leg_id', $leg->id)->whereIn('child_id', $childIds ?: [0])
            ->where('trip_boarding_id', '!=', $boarding->id)->with('boarding.worker.user')->first();

        if ($taken) {
            $child = $eligible->get((int) $taken->child_id);
            $parent = $taken->boarding && $taken->boarding->worker ? $taken->boarding->worker->fullName() : '';

            throw JsonApiException::conflict('CHILD_ALREADY_BOARDED',
                ($child ? $child->fullName() : 'El niño').' ya subió en este trayecto'.($parent ? " con {$parent}" : '').'. Cada niño cuenta una sola vez.',
                $pointer, ['childId' => (string) $taken->child_id]);
        }

        TripBoardingChild::withTrashed()->where('trip_boarding_id', $boarding->id)->forceDelete();

        foreach ($childIds as $childId) {
            TripBoardingChild::create(['trip_boarding_id' => $boarding->id, 'trip_leg_id' => $leg->id, 'child_id' => $childId]);
        }

        $boarding->forceFill(['children_count' => count($childIds)])->save();
    }

    /**
     * Quita una subida (corrección de pasajeros).
     */
    public function remove(TripBoarding $boarding): void
    {
        DB::transaction(function () use ($boarding) {
            TripBoardingChild::withTrashed()->where('trip_boarding_id', $boarding->id)->forceDelete();
            $boarding->delete();
        });
    }

    /**
     * Registro de subida de cada trabajador en el trayecto del viaje.
     *
     * @return array [id de trabajador => TripBoarding]
     */
    public function latestByWorker(int $tripId, string $direction): array
    {
        $legId = TripLeg::where('trip_id', $tripId)->where('direction', $direction)->value('id');

        if (! $legId) {
            return [];
        }

        $latest = [];

        foreach (TripBoarding::where('trip_leg_id', $legId)->orderBy('boarded_at')->orderBy('id')->get() as $boarding) {
            $latest[$boarding->worker_id] = $boarding;
        }

        return $latest;
    }

    /**
     * Hijos que subieron en el trayecto: [id de subida => int[]].
     */
    public function childIdsByBoarding(int $legId): array
    {
        $result = [];

        foreach (TripBoardingChild::where('trip_leg_id', $legId)->orderBy('child_id')->get(['trip_boarding_id', 'child_id']) as $row) {
            $result[(int) $row->trip_boarding_id][] = (int) $row->child_id;
        }

        return $result;
    }

    public function outsiderText(?string $outsider): string
    {
        if ($outsider === TripBoarding::OUTSIDER_ENTITY) {
            return 'Esta persona no pertenece a la Entidad de este viaje.';
        }

        return $outsider === TripBoarding::OUTSIDER_ITINERARY ? 'Esta persona no pertenece al itinerario de este viaje.' : '';
    }

    public function alreadyBoardedText(TripBoarding $boarding, ?string $qrKind = null): string
    {
        $time = $boarding->boarded_at ? $boarding->boarded_at->format('H:i') : '';

        if ($qrKind === QrCodes::KIND_PRINTED) {
            return "Este QR impreso ya se usó para subir en este trayecto (a las {$time}). Puede ser una copia: compruebe la identidad de la persona.";
        }

        return "Esta persona ya subió en este trayecto (a las {$time}).";
    }
}
