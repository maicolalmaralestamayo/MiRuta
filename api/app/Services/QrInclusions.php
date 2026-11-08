<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\QrNonce;
use App\Models\User;
use App\Models\Worker;
use Carbon\CarbonInterface;
use Illuminate\Support\Facades\DB;

/**
 * «Incluir por QR» (docs/11 §11.19 y §11.27): tras escanear el QR de la persona
 * se elige dónde incluirla:
 *
 * - en una Entidad (y, si se quiere, en un itinerario y una parada de ella);
 * - en un itinerario (y, si se quiere, en una de sus paradas): queda también
 *   en su Entidad;
 * - en una parada (con su itinerario, que se muestra bloqueado): queda en la
 *   Entidad y el itinerario de esa parada.
 *
 * Un solo itinerario por Entidad y una sola parada por itinerario: incluir en
 * otro itinerario de la misma Entidad le cambia el itinerario (y pierde la
 * jefatura del anterior). El Jefe solo incluye en su itinerario; el
 * Administrador, en cualquiera. Funciona sin conexión: la app guarda el
 * escaneo y lo envía después con su hora (scannedAt).
 */
class QrInclusions
{
    public const PURPOSE = 'inclusion';

    public function __construct(private QrCodes $codes, private Access $access, private Memberships $memberships)
    {
    }

    /**
     * Comprueba el QR (sin gastarlo) y dice quién es y dónde está ya.
     */
    public function describe(string $qr, User $scanner, ?CarbonInterface $scannedAt): array
    {
        if (! $this->access->isAdmin($scanner) && ! $this->access->isChief($scanner)) {
            throw Access::forbidden('Solo el Administrador y los Jefes de itinerario incluyen por QR.');
        }

        $person = $this->codes->verify($qr, $scannedAt)['user'];

        return [
            'type' => 'qr-scans',
            'id' => (string) $person->id,
            'attributes' => [
                'fullName' => $person->fullName(),
                'photoUrl' => $person->photo_path ? url($person->photo_path) : null,
                'sex' => $person->sex,
                'memberships' => $this->placesOf($person),
            ],
            'relationships' => ['user' => ['data' => ['type' => 'users', 'id' => (string) $person->id]]],
        ];
    }

    /**
     * @return array{worker: Worker, previous: array, repeated: bool}
     */
    public function include(string $qr, User $scanner, ?CarbonInterface $scannedAt, ?int $entityId, ?int $itineraryId, ?int $stopId): array
    {
        [$entity, $itinerary] = $this->target($entityId, $itineraryId, $stopId);

        if (! $this->access->isAdmin($scanner) && ! ($itinerary && $this->access->isChiefOf($scanner, $itinerary->id))) {
            throw Access::forbidden('El Jefe de itinerario solo incluye por QR en su itinerario.');
        }

        $verified = $this->codes->verify($qr, $scannedAt);
        $person = $verified['user'];
        $worker = Worker::where('user_id', $person->id)->where('entity_id', $entity->id)->first();

        // Reintento de la misma inclusión (p. ej. al sincronizar sin conexión).
        $used = QrNonce::where('user_id', $person->id)->where('nonce', $verified['nonce'])->first();

        if ($used && $used->purpose === self::PURPOSE && $worker && (int) $used->reference_id === (int) $worker->id
            && (! $itinerary || (int) $worker->itinerary_id === (int) $itinerary->id)
            && ($stopId === null || (int) $worker->stop_id === $stopId)) {
            return ['worker' => $worker, 'previous' => $this->previous($worker), 'repeated' => true];
        }

        $previous = $this->previous($worker);

        $worker = DB::transaction(function () use ($person, $entity, $itinerary, $stopId, $verified) {
            $worker = $this->memberships->join($person, $entity);

            if (! $worker->active) {
                $worker->active = true;
                $worker->save();
            }

            if ($itinerary) {
                $sameItinerary = (int) $worker->itinerary_id === (int) $itinerary->id;
                $stop = $stopId ?? ($sameItinerary ? ($worker->stop_id ? (int) $worker->stop_id : null) : null);
                $this->memberships->place($worker, (int) $itinerary->id, $stop);
            }

            $nonce = $this->codes->consume($verified, self::PURPOSE);
            $nonce?->forceFill(['reference_id' => $worker->id])->save();

            return $worker;
        });

        return ['worker' => $worker->fresh(), 'previous' => $previous, 'repeated' => false];
    }

    /**
     * @return array{0: Entity, 1: ?Itinerary}
     */
    private function target(?int $entityId, ?int $itineraryId, ?int $stopId): array
    {
        if ($stopId !== null && $itineraryId === null) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el itinerario',
                'Para incluir en una parada hay que indicar también su itinerario.', ['pointer' => '/data/relationships/itinerary']);
        }

        $itinerary = $itineraryId !== null ? Itinerary::find($itineraryId) : null;

        if ($itineraryId !== null && ! $itinerary) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El itinerario no existe.', ['pointer' => '/data/relationships/itinerary']);
        }

        if ($itinerary && $entityId !== null && (int) $itinerary->entity_id !== $entityId) {
            throw new JsonApiException(422, 'ITINERARY_NOT_IN_ENTITY', 'Itinerario de otra Entidad',
                'El itinerario no es de esa Entidad.', ['pointer' => '/data/relationships/itinerary']);
        }

        if ($itinerary && $stopId !== null && ! $itinerary->hasStop($stopId)) {
            throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario',
                'La parada no es de ese itinerario.', ['pointer' => '/data/relationships/stop']);
        }

        $entity = Entity::find($itinerary ? $itinerary->entity_id : $entityId);

        if (! $entity) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta dónde incluir',
                'Indique la Entidad, el itinerario o la parada.', ['pointer' => '/data/relationships']);
        }

        return [$entity, $itinerary];
    }

    private function previous(?Worker $worker): array
    {
        return [
            'inEntity' => $worker !== null,
            'itineraryId' => $worker && $worker->itinerary_id ? (string) $worker->itinerary_id : null,
            'stopId' => $worker && $worker->stop_id ? (string) $worker->stop_id : null,
        ];
    }

    /**
     * Dónde está ya la persona: «Ya está en la Entidad…, en el itinerario…, en la parada…».
     */
    private function placesOf(User $person): array
    {
        return Worker::where('user_id', $person->id)->with('entity', 'itinerary', 'stop')->get()->map(fn (Worker $w) => [
            'workerId' => (string) $w->id,
            'entity' => ['id' => (string) $w->entity_id, 'abbreviation' => $w->entity?->abbreviation, 'name' => $w->entity?->name],
            'itinerary' => $w->itinerary ? ['id' => (string) $w->itinerary_id, 'name' => $w->itinerary->name] : null,
            'stop' => $w->stop ? ['id' => (string) $w->stop_id, 'landmark' => $w->stop->landmark] : null,
            'isChief' => (bool) $w->is_chief,
        ])->values()->all();
    }
}
