<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\User;
use App\Models\Worker;
use Illuminate\Support\Facades\DB;

/**
 * La persona en las Entidades (docs/11 §11.23 a §11.30): un solo itinerario
 * por Entidad y una sola parada por itinerario, los dos opcionales. Un Jefe
 * lo es de un solo itinerario y viaja en él: si se le cambia (o se le saca)
 * de su itinerario, deja de ser Jefe.
 */
class Memberships
{
    public function __construct(private Access $access)
    {
    }

    /**
     * Añade a la persona a la Entidad (si ya está, devuelve su pertenencia).
     */
    public function join(User $user, Entity $entity): Worker
    {
        $worker = Worker::firstOrCreate(['user_id' => $user->id, 'entity_id' => $entity->id], ['active' => true]);
        $this->access->flush($user->id);

        return $worker;
    }

    /**
     * Pone (o quita, con null) el itinerario y la parada. El itinerario tiene
     * que ser de la Entidad de la pertenencia y la parada, del itinerario.
     */
    public function place(Worker $worker, ?int $itineraryId, ?int $stopId): Worker
    {
        if ($itineraryId !== null) {
            $itinerary = Itinerary::find($itineraryId);

            if (! $itinerary || (int) $itinerary->entity_id !== (int) $worker->entity_id) {
                throw new JsonApiException(422, 'ITINERARY_NOT_IN_ENTITY', 'Itinerario de otra Entidad',
                    'El itinerario no es de la Entidad de esta persona.', ['pointer' => '/data/relationships/itinerary']);
            }

            if ($stopId !== null && ! $itinerary->hasStop($stopId)) {
                throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario',
                    'La parada no es de ese itinerario.', ['pointer' => '/data/relationships/stop']);
            }
        } elseif ($stopId !== null) {
            throw new JsonApiException(422, 'STOP_WITHOUT_ITINERARY', 'Falta el itinerario',
                'Para tener parada hay que estar en un itinerario.', ['pointer' => '/data/relationships/stop']);
        }

        $changedItinerary = (int) $worker->itinerary_id !== (int) $itineraryId;
        $worker->itinerary_id = $itineraryId;
        $worker->stop_id = $stopId;

        // Cambiar de itinerario (o salir de él) quita la jefatura (docs/11 §11.30).
        if ($changedItinerary) {
            $worker->is_chief = false;
        }

        $worker->save();
        $this->access->flush((int) $worker->user_id);

        return $worker;
    }

    /**
     * Nombra Jefe de ese itinerario (lo pone en él si no lo estaba). Deja de
     * ser Jefe de cualquier otro.
     */
    public function makeChief(Worker $worker, int $itineraryId): Worker
    {
        return DB::transaction(function () use ($worker, $itineraryId) {
            Worker::where('user_id', $worker->user_id)->where('id', '<>', $worker->id)->update(['is_chief' => false]);

            if ((int) $worker->itinerary_id !== $itineraryId) {
                $this->place($worker, $itineraryId, null);
            }

            $worker->is_chief = true;
            $worker->save();
            $this->access->flush((int) $worker->user_id);

            return $worker;
        });
    }

    public function removeChief(Worker $worker): Worker
    {
        $worker->is_chief = false;
        $worker->save();
        $this->access->flush((int) $worker->user_id);

        return $worker;
    }

    /**
     * Sale de la Entidad (o lo sacan): se borran su itinerario, su parada, su
     * jefatura y sus ausencias allí, y sus solicitudes de itinerario pendientes.
     */
    public function leave(Worker $worker): void
    {
        DB::transaction(function () use ($worker) {
            Application::where('user_id', $worker->user_id)->where('entity_id', $worker->entity_id)
                ->where('status', Application::PENDING)->delete();
            $worker->delete();
        });
        $this->access->flush((int) $worker->user_id);
    }
}
