<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Services\Access;
use App\Services\Organization;
use Illuminate\Http\Request;

/**
 * Paradas de un itinerario («Añadir parada existente», «Quitar del
 * itinerario», mover). Las gestionan el Administrador y los Jefes del itinerario.
 */
class ItineraryStopController extends Controller
{
    public const INCLUDABLE = ['itinerary', 'stop'];

    public function __construct(private Access $access, private Organization $organization)
    {
    }

    public function index(Request $request)
    {
        $sortable = ['position' => 'position', 'id' => 'id'];
        $parameters = QueryParameters::fromRequest($request, $sortable, ['itinerary', 'stop'], self::INCLUDABLE, 'position');
        $query = ItineraryStop::query();
        $user = $request->user();

        if (! $this->access->isAdmin($user)) {
            $query->whereIn('itinerary_id', Itinerary::whereIn('entity_id', $this->access->entityIds($user) ?: [0])->select('id'));
        }

        foreach (['itinerary' => 'itinerary_id', 'stop' => 'stop_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, (int) $value);
            }
        }

        return $this->paginate($request, $query, $parameters, $sortable);
    }

    /**
     * Añade una parada existente al itinerario (attributes.position opcional; por omisión, al final).
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'itinerary-stops', [
            'attributes.position' => ['sometimes', 'nullable', 'integer', 'min:1'],
        ] + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', true) + $this->relationshipRules('stop', 'stops', 'stops', true));
        $itinerary = Itinerary::findOrFail($this->relationshipId($data, 'itinerary'));
        $this->access->requireItineraryManager($request->user(), $itinerary->id, 'Solo el Administrador o el Jefe del itinerario le añaden paradas.');
        $link = $this->organization->addStop($itinerary, Stop::findOrFail($this->relationshipId($data, 'stop')),
            isset($data['attributes']['position']) ? (int) $data['attributes']['position'] : null);

        return $this->created($request, $link->fresh(), 'itinerary-stops');
    }

    /**
     * Mueve la parada a otra posición.
     */
    public function update(Request $request, $id)
    {
        $link = ItineraryStop::findOrFail($id);
        $this->access->requireItineraryManager($request->user(), $link->itinerary_id, 'Solo el Administrador o el Jefe del itinerario ordenan sus paradas.');
        $data = $this->validateResource($request, 'itinerary-stops', ['attributes.position' => ['required', 'integer', 'min:1']]);

        return $this->respond($request, $this->organization->move($link, (int) $data['attributes']['position']));
    }

    /**
     * Quita la parada del itinerario (la parada se conserva; quien la tenía queda sin parada).
     */
    public function destroy(Request $request, $id)
    {
        $link = ItineraryStop::findOrFail($id);
        $this->access->requireItineraryManager($request->user(), $link->itinerary_id, 'Solo el Administrador o el Jefe del itinerario le quitan paradas.');
        $this->organization->removeStop($link);

        return $this->noContent();
    }
}
