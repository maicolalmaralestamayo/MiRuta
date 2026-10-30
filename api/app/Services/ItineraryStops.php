<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Worker;
use Illuminate\Support\Facades\DB;

/**
 * Orden de las paradas de un itinerario. Las posiciones van de 1 a n sin
 * huecos; una parada quitada (borrada) queda con posición NULL.
 */
class ItineraryStops
{
    /**
     * Añade la parada en la posición indicada (al final si es null) y
     * desplaza las siguientes.
     */
    public function add(int $itineraryId, int $stopId, ?int $position): ItineraryStop
    {
        $existing = ItineraryStop::withTrashed()->where('itinerary_id', $itineraryId)->where('stop_id', $stopId)->first();

        if ($existing && ! $existing->trashed()) {
            throw JsonApiException::conflict('STOP_ALREADY_IN_ITINERARY', 'Esa parada ya está en el itinerario.', '/data/relationships/stop');
        }

        $before = $this->extremes($itineraryId);
        $itineraryStop = $existing ?: new ItineraryStop(['itinerary_id' => $itineraryId, 'stop_id' => $stopId]);
        $itineraryStop->deleted_at = null;
        $itineraryStop->position = null;
        $itineraryStop->save();

        $ids = $this->orderedIds($itineraryId, $itineraryStop->id);
        array_splice($ids, $this->clamp($position, count($ids) + 1) - 1, 0, [$itineraryStop->id]);
        $this->renumber($itineraryId, $ids);
        $this->notifyIfExtremesChanged($itineraryId, $before);

        return $itineraryStop->fresh();
    }

    public function move(ItineraryStop $itineraryStop, int $position): ItineraryStop
    {
        $before = $this->extremes($itineraryStop->itinerary_id);
        $ids = $this->orderedIds($itineraryStop->itinerary_id, $itineraryStop->id);
        array_splice($ids, $this->clamp($position, count($ids) + 1) - 1, 0, [$itineraryStop->id]);
        $this->renumber($itineraryStop->itinerary_id, $ids);
        $this->notifyIfExtremesChanged($itineraryStop->itinerary_id, $before);

        return $itineraryStop->fresh();
    }

    /**
     * Quita la parada del itinerario. No se puede si hay miembros en ella.
     */
    public function remove(ItineraryStop $itineraryStop): void
    {
        $hasMembers = Worker::where('itinerary_id', $itineraryStop->itinerary_id)
            ->where('stop_id', $itineraryStop->stop_id)
            ->exists();

        if ($hasMembers) {
            throw JsonApiException::conflict('STOP_HAS_MEMBERS', 'Hay trabajadores en esa parada. Primero hay que cambiarles la parada.');
        }

        $before = $this->extremes($itineraryStop->itinerary_id);
        $itineraryStop->position = null;
        $itineraryStop->save();
        $itineraryStop->delete();
        $this->renumber($itineraryStop->itinerary_id, $this->orderedIds($itineraryStop->itinerary_id));
        $this->notifyIfExtremesChanged($itineraryStop->itinerary_id, $before);
    }

    /**
     * @return int[] ids de itinerary_stop activos en orden, sin $exceptId
     */
    private function orderedIds(int $itineraryId, ?int $exceptId = null): array
    {
        $query = ItineraryStop::where('itinerary_id', $itineraryId)->whereNotNull('position')->orderBy('position');

        if ($exceptId) {
            $query->where('id', '!=', $exceptId);
        }

        return array_map('intval', $query->pluck('id')->all());
    }

    /**
     * Asigna 1..n. Primero se vacían las posiciones para no chocar con la
     * clave única (itinerario, posición) mientras se reordena.
     */
    private function renumber(int $itineraryId, array $ids): void
    {
        DB::table('itinerary_stop')->where('itinerary_id', $itineraryId)->update(['position' => null]);

        foreach ($ids as $index => $id) {
            DB::table('itinerary_stop')->where('id', $id)->update(['position' => $index + 1]);
        }
    }

    private function clamp(?int $position, int $max): int
    {
        return $position === null ? $max : max(1, min($position, $max));
    }

    /**
     * @return array [id de la primera parada, id de la última]
     */
    private function extremes(int $itineraryId): array
    {
        $stops = ItineraryStop::where('itinerary_id', $itineraryId)->whereNotNull('position')->orderBy('position')->pluck('stop_id');

        return [$stops->first(), $stops->last()];
    }

    /**
     * Si cambian los puntos de salida o de regreso, se marcan como modificados
     * los viajes pendientes para que las apps lo detecten al sincronizar.
     */
    private function notifyIfExtremesChanged(int $itineraryId, array $before): void
    {
        if ($before !== $this->extremes($itineraryId)) {
            Itinerary::whereKey($itineraryId)->first()->touchPendingTrips();
        }
    }
}
