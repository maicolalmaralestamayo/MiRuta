<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\ItineraryStop;
use App\Services\ItineraryStops;
use App\Services\Permissions;
use App\Support\Tenancy;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Paradas de un itinerario y su orden. Al añadir, mover o quitar una parada
 * se renumeran las demás.
 */
class ItineraryStopController extends ResourceController
{
    protected $model = ItineraryStop::class;

    protected $type = 'itinerary-stops';

    protected $sortable = ['position' => 'position'];

    protected $filterable = ['itinerary'];

    protected $includable = ['stop', 'itinerary'];

    protected $defaultSort = 'position';

    protected $manageOperation = 'itineraries.manage';

    protected $viewOperation = 'itineraries.view';

    /** @var ItineraryStops */
    private $itineraryStops;

    public function __construct(ItineraryStops $itineraryStops)
    {
        $this->itineraryStops = $itineraryStops;
    }

    protected function rules(Request $request, ?Model $model): array
    {
        if ($model) {
            return ['attributes.position' => ['required', 'integer', 'min:1']];
        }

        return array_merge(
            ['attributes.position' => ['sometimes', 'nullable', 'integer', 'min:1']],
            $this->relationshipRules('itinerary', 'itineraries', 'itineraries', true),
            $this->relationshipRules('stop', 'stops', 'stops', true)
        );
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($itinerary = $parameters->filter('itinerary')) {
            $query->where('itinerary_id', $itinerary);
        }
    }

    protected function newQuery(Request $request): Builder
    {
        $entities = $this->visibleEntityIds($request);

        return ItineraryStop::query()->whereHas('itinerary', function (Builder $query) use ($entities) {
            $query->whereIn('entity_id', $entities);
        });
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, $this->type, $this->rules($request, null));
        $position = isset($data['attributes']['position']) ? (int) $data['attributes']['position'] : null;
        $itineraryId = (int) $data['relationships']['itinerary']['data']['id'];

        // Puede gestionar los itinerarios de esa Entidad y la parada es de la misma.
        app(Permissions::class)->authorize($request->user(), 'itineraries.manage', Tenancy::entityOf('itineraries', $itineraryId));
        Tenancy::ensureSame(Tenancy::entityOf('itineraries', $itineraryId), 'stops',
            (int) $data['relationships']['stop']['data']['id'], '/data/relationships/stop');

        $itineraryStop = DB::transaction(function () use ($data, $position) {
            return $this->itineraryStops->add(
                (int) $data['relationships']['itinerary']['data']['id'],
                (int) $data['relationships']['stop']['data']['id'],
                $position
            );
        });

        return JsonApiResponse::make((new Document($request))->resource($itineraryStop), 201, [
            'Location' => url('api/v1/itinerary-stops/'.$itineraryStop->id),
        ]);
    }

    public function update(Request $request, $id)
    {
        $itineraryStop = $this->findOrFail($request, $id);
        // Ordenar: itineraries.order_stops sobre el itinerario (o gestionar los itinerarios).
        $permissions = app(Permissions::class);
        $entityId = Tenancy::entityOf('itineraries', $itineraryStop->itinerary_id);

        if (! $permissions->can($request->user(), 'itineraries.order_stops', $entityId, (int) $itineraryStop->itinerary_id)) {
            $permissions->authorize($request->user(), 'itineraries.manage', $entityId);
        }
        $data = $this->validateResource($request, $this->type, $this->rules($request, $itineraryStop));

        $itineraryStop = DB::transaction(function () use ($itineraryStop, $data) {
            return $this->itineraryStops->move($itineraryStop, (int) $data['attributes']['position']);
        });

        return JsonApiResponse::make((new Document($request))->resource($itineraryStop));
    }

    public function destroy(Request $request, $id)
    {
        $itineraryStop = $this->findOrFail($request, $id);
        app(Permissions::class)->authorize($request->user(), 'itineraries.manage', Tenancy::entityOf('itineraries', $itineraryStop->itinerary_id));

        DB::transaction(function () use ($itineraryStop) {
            $this->itineraryStops->remove($itineraryStop);
        });

        return response('', 204);
    }
}
