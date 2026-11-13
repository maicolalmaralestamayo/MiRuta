<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use Illuminate\Support\Facades\DB;

/**
 * La persona en las Entidades y en sus itinerarios (docs/11 §11.58): puede
 * estar en varias Entidades y, en cada una, en varios itinerarios, cada uno
 * con su parada (opcional). Un Jefe lo es de un solo itinerario y viaja en él:
 * si sale de ese itinerario, deja de ser Jefe.
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
     * Añade a la persona a un itinerario (y a su Entidad, si no estaba), con
     * parada opcional. Si ya estaba, solo cambia la parada (si se indica).
     */
    public function addItinerary(User $user, Itinerary $itinerary, ?int $stopId = null): WorkerItinerary
    {
        if (! $itinerary->entity_id) {
            throw JsonApiException::conflict('ITINERARY_WITHOUT_ENTITY',
                'Ese itinerario no tiene Entidad: asóciele una antes de añadirle personas.', '/data/relationships/itinerary');
        }

        $this->checkStop($itinerary, $stopId);

        return DB::transaction(function () use ($user, $itinerary, $stopId) {
            $worker = $this->join($user, Entity::findOrFail($itinerary->entity_id));
            $placement = WorkerItinerary::where('user_id', $user->id)->where('itinerary_id', $itinerary->id)->first();

            if (! $placement) {
                $placement = WorkerItinerary::create([
                    'worker_id' => $worker->id, 'user_id' => $user->id, 'itinerary_id' => $itinerary->id, 'stop_id' => $stopId,
                ]);
            } elseif ($stopId !== null && (int) $placement->stop_id !== $stopId) {
                $placement->stop_id = $stopId;
                $placement->save();
            }

            $this->access->flush($user->id);

            return $placement;
        });
    }

    /**
     * Pone (o quita, con null) la parada de la persona en ese itinerario.
     */
    public function setStop(WorkerItinerary $placement, ?int $stopId): WorkerItinerary
    {
        $this->checkStop(Itinerary::findOrFail($placement->itinerary_id), $stopId);
        $placement->stop_id = $stopId;
        $placement->save();
        $this->access->flush((int) $placement->user_id);

        return $placement;
    }

    /**
     * Nombra Jefe de ese itinerario; deja de serlo de cualquier otro.
     */
    public function makeChief(WorkerItinerary $placement): WorkerItinerary
    {
        DB::transaction(function () use ($placement) {
            WorkerItinerary::where('user_id', $placement->user_id)->where('id', '<>', $placement->id)->update(['is_chief' => false]);
            $placement->is_chief = true;
            $placement->save();
        });
        $this->access->flush((int) $placement->user_id);

        return $placement;
    }

    public function removeChief(WorkerItinerary $placement): WorkerItinerary
    {
        $placement->is_chief = false;
        $placement->save();
        $this->access->flush((int) $placement->user_id);

        return $placement;
    }

    /**
     * Sale del itinerario (con su parada y su jefatura en él). Sigue en la Entidad.
     */
    public function leaveItinerary(WorkerItinerary $placement): void
    {
        $placement->delete();
        $this->access->flush((int) $placement->user_id);
    }

    /**
     * Sale de la Entidad (o lo sacan): se borran sus itinerarios allí (con su
     * parada y su jefatura), sus ausencias y sus solicitudes pendientes en ella.
     */
    public function leave(Worker $worker): void
    {
        DB::transaction(function () use ($worker) {
            Application::where('user_id', $worker->user_id)->where('entity_id', $worker->entity_id)
                ->where('status', Application::PENDING)->delete();
            WorkerItinerary::where('worker_id', $worker->id)->delete();
            $worker->delete();
        });
        $this->access->flush((int) $worker->user_id);
    }

    /**
     * El itinerario cambió de Entidad (o se quedó sin ella): sus personas pasan
     * con él a la nueva Entidad (se las añade si no estaban); sin Entidad, salen
     * del itinerario. Sus solicitudes pendientes siguen al itinerario (o se borran).
     */
    public function itineraryMoved(Itinerary $itinerary, ?int $entityId): void
    {
        DB::transaction(function () use ($itinerary, $entityId) {
            $placements = WorkerItinerary::where('itinerary_id', $itinerary->id)->get();

            if ($entityId === null) {
                WorkerItinerary::where('itinerary_id', $itinerary->id)->delete();
                Application::where('itinerary_id', $itinerary->id)->where('status', Application::PENDING)->delete();
            } else {
                $entity = Entity::findOrFail($entityId);

                foreach ($placements as $placement) {
                    $worker = $this->join(User::findOrFail($placement->user_id), $entity);
                    $placement->worker_id = $worker->id;
                    $placement->save();
                }

                Application::where('itinerary_id', $itinerary->id)->update(['entity_id' => $entityId]);
            }
        });
        $this->access->flush();
    }

    private function checkStop(Itinerary $itinerary, ?int $stopId): void
    {
        if ($stopId !== null && ! $itinerary->hasStop($stopId)) {
            throw new JsonApiException(422, 'STOP_NOT_IN_ITINERARY', 'Parada de otro itinerario',
                'La parada no es de ese itinerario.', ['pointer' => '/data/relationships/stop']);
        }
    }
}
