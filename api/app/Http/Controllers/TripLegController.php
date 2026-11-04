<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Services\Tracking;
use App\Services\Trips;
use Illuminate\Http\Request;

class TripLegController extends TrackingController
{
    const SORTABLE = ['startedAt' => 'started_at', 'id' => 'id'];

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['trip', 'active'], ['trip'], 'startedAt');
        $query = $this->visibleLegs($request);

        if ($trip = $parameters->filter('trip')) {
            $query->where('trip_id', $trip);
        }

        if ($parameters->filter('active') === 'true') {
            $query->whereNull('ended_at');
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->findLeg($request, $id), QueryParameters::readIncludes($request, ['trip'])));
    }

    /**
     * Iniciar recorrido.
     */
    public function store(Request $request, Tracking $tracking, Trips $trips)
    {
        $data = $this->validateResource($request, 'trip-legs', [
            'attributes.direction' => ['required', 'in:outbound,return'],
            'relationships.trip.data.type' => ['required', 'in:trips'],
            'relationships.trip.data.id' => ['required', 'integer'],
        ]);

        $trip = $trips->visibleTo($request->user())->find($data['relationships']['trip']['data']['id']);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        $leg = $tracking->start($trip, $data['attributes']['direction'], $request->user());

        return JsonApiResponse::make((new Document($request))->resource($leg->fresh()), 201, ['Location' => url('api/v1/trip-legs/'.$leg->id)]);
    }

    /**
     * Finalizar recorrido (attributes.endedAt con cualquier fecha: se usa la hora del servidor).
     */
    public function update(Request $request, Tracking $tracking, $id)
    {
        $leg = $this->findLeg($request, $id);
        $this->validateResource($request, 'trip-legs', ['attributes.endedAt' => ['required', 'date']]);

        return JsonApiResponse::make((new Document($request))->resource($tracking->end($leg, $request->user())->fresh()));
    }
}
