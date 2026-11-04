<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripCompletion;
use App\Services\Trips;
use Illuminate\Http\Request;

/**
 * Marcas de "viaje realizado".
 */
class TripCompletionController extends Controller
{
    /** @var Trips */
    private $trips;

    public function __construct(Trips $trips)
    {
        $this->trips = $trips;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['trip'], ['user'], 'createdAt');
        $visibleTrips = $this->trips->visibleTo($request->user())->select('id');
        $query = TripCompletion::whereIn('trip_id', $visibleTrips);

        if ($trip = $parameters->filter('trip')) {
            $query->where('trip_id', $trip);
        }

        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'trip-completions', [
            'relationships.trip.data.type' => ['required', 'in:trips'],
            'relationships.trip.data.id' => ['required', 'integer'],
        ]);

        $trip = $this->trips->visibleTo($request->user())->find($data['relationships']['trip']['data']['id']);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        $completion = $this->trips->markCompleted($trip, $request->user());

        return JsonApiResponse::make((new Document($request))->resource($completion->fresh()), 201);
    }
}
