<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\Boardings;
use App\Services\Trips;
use Illuminate\Http\Request;

/**
 * Pasajeros esperados de un viaje en orden de subida (7.21), con su estado
 * de subida en el trayecto indicado.
 */
class TripPassengerController extends Controller
{
    public function index(Request $request, Trips $trips, Boardings $boardings, $id)
    {
        $user = $request->user();
        $trip = $trips->visibleTo($user)->find($id);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puedes verlo.');
        }

        $stop = $request->input('filter.stop');
        $direction = $request->input('filter.direction', 'return');

        if (! in_array($direction, ['outbound', 'return'], true)) {
            throw JsonApiException::badRequest('filter[direction] debe ser outbound o return.', 'filter[direction]');
        }

        $latest = $boardings->latestByWorker($trip->id, $direction);
        $document = new Document($request);
        $data = [];
        $included = [];

        foreach ($trips->passengerList($trip, $stop ? (int) $stop : null) as $index => $item) {
            $worker = $item['worker'];
            $boarding = isset($latest[$worker->id]) ? $latest[$worker->id] : null;

            $data[] = [
                'type' => 'trip-passengers',
                'id' => $trip->id.'-'.$worker->id,
                'attributes' => [
                    'position' => $index + 1,
                    'eligibleChildren' => $item['children'],
                    'boarded' => $boarding !== null,
                    'boardedChildren' => $boarding ? (int) $boarding->children_count : null,
                    'boardingMethod' => $boarding ? $boarding->method : null,
                ],
                'relationships' => [
                    'worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]],
                    'stop' => ['data' => ['type' => 'stops', 'id' => (string) $worker->stop_id]],
                ],
            ];
            $included['workers:'.$worker->id] = $document->resourceObjectFor($worker);
            $included['users:'.$worker->user_id] = $document->resourceObjectFor($worker->user);
            $included['ranks:'.$worker->rank_id] = $document->resourceObjectFor($worker->rank);
        }

        $result = Document::fromArray($data, ['total' => count($data), 'direction' => $direction]);
        $result['included'] = array_values($included);

        return JsonApiResponse::make($result);
    }
}
