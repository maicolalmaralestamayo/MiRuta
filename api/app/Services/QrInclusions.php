<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\QrNonce;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Http\Controllers\MeController;
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
 * Incluir AÑADE la Entidad o el itinerario a los que ya tiene (docs/11 §11.58:
 * varios itinerarios por Entidad, cada uno con su parada); si ya estaba en el
 * itinerario, solo se le pone la parada indicada. El Jefe solo incluye en su itinerario; el
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
     * @return array{worker: Worker, placement: ?WorkerItinerary, previous: array, repeated: bool}
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
        $placement = $itinerary ? WorkerItinerary::where('user_id', $person->id)->where('itinerary_id', $itinerary->id)->first() : null;

        // Reintento de la misma inclusión (p. ej. al sincronizar sin conexión).
        $used = QrNonce::where('user_id', $person->id)->where('nonce', $verified['nonce'])->first();

        if ($used && $used->purpose === self::PURPOSE && $worker && (int) $used->reference_id === (int) $worker->id
            && (! $itinerary || $placement)
            && ($stopId === null || ($placement && (int) $placement->stop_id === $stopId))) {
            return ['worker' => $worker, 'placement' => $placement, 'previous' => $this->previous($worker, $placement), 'repeated' => true];
        }

        $previous = $this->previous($worker, $placement);

        [$worker, $placement] = DB::transaction(function () use ($person, $entity, $itinerary, $stopId, $verified) {
            $worker = $this->memberships->join($person, $entity);

            if (! $worker->active) {
                $worker->active = true;
                $worker->save();
            }

            $placement = $itinerary ? $this->memberships->addItinerary($person, $itinerary, $stopId) : null;

            $nonce = $this->codes->consume($verified, self::PURPOSE);
            $nonce?->forceFill(['reference_id' => $worker->id])->save();

            return [$worker, $placement];
        });

        return ['worker' => $worker->fresh(), 'placement' => $placement?->fresh(), 'previous' => $previous, 'repeated' => false];
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

        if ($itinerary && ! $itinerary->entity_id) {
            throw JsonApiException::conflict('ITINERARY_WITHOUT_ENTITY', 'Ese itinerario no tiene Entidad: asóciele una antes de incluir personas.', '/data/relationships/itinerary');
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

    private function previous(?Worker $worker, ?WorkerItinerary $placement): array
    {
        return [
            'inEntity' => $worker !== null,
            'inItinerary' => $placement !== null,
            'stopId' => $placement && $placement->stop_id ? (string) $placement->stop_id : null,
        ];
    }

    /**
     * Dónde está ya la persona: sus Entidades, cada una con sus itinerarios y paradas.
     */
    private function placesOf(User $person): array
    {
        return MeController::memberships($person);
    }
}
