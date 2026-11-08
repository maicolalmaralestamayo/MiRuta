<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\Worker;
use Illuminate\Support\Facades\DB;

/**
 * Entidades, itinerarios y paradas: eliminaciones en cascada y paradas de un
 * itinerario (docs/11 §11.22 y §11.24).
 *
 * - Entidad: se eliminan sus itinerarios (con sus viajes y solicitudes); las
 *   personas no se eliminan: quedan sin esa Entidad.
 * - Itinerario: sus personas quedan sin itinerario, sin parada y sin jefatura;
 *   las paradas se conservan (pueden estar en otros itinerarios).
 * - Parada: las personas que la tenían quedan sin parada (conservan su itinerario).
 */
class Organization
{
    public function __construct(private Access $access)
    {
    }

    public function deleteEntity(Entity $entity): void
    {
        DB::transaction(function () use ($entity) {
            foreach (Itinerary::where('entity_id', $entity->id)->get() as $itinerary) {
                $this->deleteItinerary($itinerary);
            }

            Application::where('entity_id', $entity->id)->delete();
            Worker::where('entity_id', $entity->id)->delete();
            $entity->delete();
        });
        $this->access->flush();
    }

    public function deleteItinerary(Itinerary $itinerary): void
    {
        DB::transaction(function () use ($itinerary) {
            Worker::where('itinerary_id', $itinerary->id)->update(['itinerary_id' => null, 'stop_id' => null, 'is_chief' => false]);
            $itinerary->delete();
        });
        $this->access->flush();
    }

    public function deleteStop(Stop $stop): void
    {
        DB::transaction(function () use ($stop) {
            $itineraryIds = ItineraryStop::where('stop_id', $stop->id)->pluck('itinerary_id')->all();
            Worker::where('stop_id', $stop->id)->update(['stop_id' => null]);
            $stop->delete();

            foreach ($itineraryIds as $itineraryId) {
                $this->renumber((int) $itineraryId);
            }
        });
    }

    /**
     * Añade una parada al itinerario en esa posición (por omisión, al final).
     */
    public function addStop(Itinerary $itinerary, Stop $stop, ?int $position = null): ItineraryStop
    {
        if ($itinerary->hasStop($stop->id)) {
            throw JsonApiException::conflict('STOP_ALREADY_IN_ITINERARY', 'La parada ya está en ese itinerario.', '/data/relationships/stop');
        }

        return DB::transaction(function () use ($itinerary, $stop, $position) {
            $count = ItineraryStop::where('itinerary_id', $itinerary->id)->count();
            $position = $position === null ? $count + 1 : max(1, min($position, $count + 1));
            ItineraryStop::where('itinerary_id', $itinerary->id)->where('position', '>=', $position)->increment('position');

            return ItineraryStop::create(['itinerary_id' => $itinerary->id, 'stop_id' => $stop->id, 'position' => $position]);
        });
    }

    /**
     * Quita la parada del itinerario (la parada se conserva). Quien la tenía
     * en ese itinerario queda sin parada.
     */
    public function removeStop(ItineraryStop $link): void
    {
        DB::transaction(function () use ($link) {
            Worker::where('itinerary_id', $link->itinerary_id)->where('stop_id', $link->stop_id)->update(['stop_id' => null]);
            Application::where('itinerary_id', $link->itinerary_id)->where('stop_id', $link->stop_id)
                ->where('status', Application::PENDING)->update(['stop_id' => null]);
            $link->delete();
            $this->renumber((int) $link->itinerary_id);
        });
    }

    /**
     * Mueve una parada a otra posición.
     */
    public function move(ItineraryStop $link, int $position): ItineraryStop
    {
        $ids = ItineraryStop::where('itinerary_id', $link->itinerary_id)->orderBy('position')->pluck('stop_id')->map(fn ($id) => (int) $id)->all();
        $ids = array_values(array_diff($ids, [(int) $link->stop_id]));
        $position = max(1, min($position, count($ids) + 1));
        array_splice($ids, $position - 1, 0, [(int) $link->stop_id]);
        $this->reorder(Itinerary::findOrFail($link->itinerary_id), $ids);

        return $link->fresh();
    }

    /**
     * Nuevo orden de todas las paradas del itinerario (arrastrar).
     *
     * @param int[] $stopIds
     */
    public function reorder(Itinerary $itinerary, array $stopIds): void
    {
        $current = $itinerary->stopIds();
        $stopIds = array_map('intval', $stopIds);
        $sortedNew = $stopIds;
        $sortedCurrent = $current;
        sort($sortedNew);
        sort($sortedCurrent);

        if ($sortedNew !== $sortedCurrent) {
            throw new JsonApiException(422, 'STOP_ORDER_INVALID', 'Orden no válido',
                'Hay que enviar todas las paradas del itinerario, cada una una vez.', ['pointer' => '/data']);
        }

        DB::transaction(function () use ($itinerary, $stopIds) {
            foreach ($stopIds as $index => $stopId) {
                ItineraryStop::where('itinerary_id', $itinerary->id)->where('stop_id', $stopId)->update(['position' => $index + 1]);
            }
        });
    }

    private function renumber(int $itineraryId): void
    {
        foreach (ItineraryStop::where('itinerary_id', $itineraryId)->orderBy('position')->get() as $index => $link) {
            if ((int) $link->position !== $index + 1) {
                $link->position = $index + 1;
                $link->save();
            }
        }
    }
}
