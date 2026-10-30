<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\ItineraryStop;
use App\Services\ItineraryStops;
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

    public function store(Request $request)
    {
        $this->authorize('create', ItineraryStop::class);
        $data = $this->validateResource($request, $this->type, $this->rules($request, null));
        $position = isset($data['attributes']['position']) ? (int) $data['attributes']['position'] : null;

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
        $itineraryStop = ItineraryStop::findOrFail($id);
        $this->authorize('update', $itineraryStop);
        $data = $this->validateResource($request, $this->type, $this->rules($request, $itineraryStop));

        $itineraryStop = DB::transaction(function () use ($itineraryStop, $data) {
            return $this->itineraryStops->move($itineraryStop, (int) $data['attributes']['position']);
        });

        return JsonApiResponse::make((new Document($request))->resource($itineraryStop));
    }

    public function destroy(Request $request, $id)
    {
        $itineraryStop = ItineraryStop::findOrFail($id);
        $this->authorize('delete', $itineraryStop);

        DB::transaction(function () use ($itineraryStop) {
            $this->itineraryStops->remove($itineraryStop);
        });

        return response('', 204);
    }
}
