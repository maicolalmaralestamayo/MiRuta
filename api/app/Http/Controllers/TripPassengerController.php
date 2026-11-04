<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\Boardings;
use App\Services\Trips;
use App\Models\Worker;
use Illuminate\Http\Request;

/**
 * Pasajeros esperados de un viaje en orden de subida (7.21), con su estado
 * de subida en el trayecto indicado (hijos que subieron con cada uno) y, al
 * final, quienes subieron sin ser esperados (expected = false).
 */
class TripPassengerController extends Controller
{
    public function index(Request $request, Trips $trips, Boardings $boardings, $id)
    {
        $user = $request->user();
        $trip = $trips->visibleTo($user)->find($id);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        $stop = $request->input('filter.stop');
        $direction = $request->input('filter.direction', 'return');

        if (! in_array($direction, ['outbound', 'return'], true)) {
            throw JsonApiException::badRequest('filter[direction] debe ser outbound o return.', 'filter[direction]');
        }

        $latest = $boardings->latestByWorker($trip->id, $direction);
        $legId = \App\Models\TripLeg::where('trip_id', $trip->id)->where('direction', $direction)->value('id');
        $children = $legId ? $boardings->childIdsByBoarding((int) $legId) : [];
        $document = new Document($request);
        $data = [];
        $included = [];
        $row = function (Worker $worker, int $position, bool $expected, ?int $eligible) use ($trip, $latest, $children, $document, &$data, &$included) {
            $boarding = isset($latest[$worker->id]) ? $latest[$worker->id] : null;
            $childIds = $boarding && isset($children[$boarding->id]) ? $children[$boarding->id] : [];

            $data[] = [
                'type' => 'trip-passengers',
                'id' => $trip->id.'-'.$worker->id,
                'attributes' => [
                    'position' => $position,
                    'expected' => $expected,
                    'eligibleChildren' => $eligible,
                    'boarded' => $boarding !== null,
                    'boardedChildren' => $boarding ? count($childIds) : null,
                    'boardedChildIds' => array_map('strval', $childIds),
                    'boardingMethod' => $boarding ? $boarding->method : null,
                    'outsider' => $boarding ? $boarding->outsider : null,
                ],
                'relationships' => [
                    'worker' => ['data' => ['type' => 'workers', 'id' => (string) $worker->id]],
                    'stop' => ['data' => $worker->stop_id ? ['type' => 'stops', 'id' => (string) $worker->stop_id] : null],
                    'tripBoarding' => ['data' => $boarding ? ['type' => 'trip-boardings', 'id' => (string) $boarding->id] : null],
                ],
            ];
            $included['workers:'.$worker->id] = $document->resourceObjectFor($worker);
            $included['users:'.$worker->user_id] = $document->resourceObjectFor($worker->user);
        };

        $listed = [];

        foreach ($trips->passengerList($trip, $stop ? (int) $stop : null) as $index => $item) {
            $row($item['worker'], $index + 1, true, $item['children']);
            $listed[(int) $item['worker']->id] = true;
        }

        // Quienes subieron sin ser pasajeros esperados (de otro itinerario o Entidad, ausentes…), al final.
        if (! $stop) {
            foreach ($latest as $workerId => $boarding) {
                if (! isset($listed[(int) $workerId]) && ($worker = Worker::withTrashed()->with('user')->find($workerId))) {
                    $row($worker, count($data) + 1, false, null);
                }
            }
        }

        $result = Document::fromArray($data, ['total' => count($data), 'direction' => $direction]);
        $result['included'] = array_values($included);

        return JsonApiResponse::make($result);
    }
}
