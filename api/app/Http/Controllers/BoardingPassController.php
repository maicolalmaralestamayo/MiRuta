<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\Boardings;
use App\Services\Trips;
use Illuminate\Http\Request;

/**
 * Token del código QR del trabajador autenticado para un trayecto.
 */
class BoardingPassController extends TrackingController
{
    public function store(Request $request, Boardings $boardings, Trips $trips)
    {
        $data = $this->validateResource($request, 'boarding-passes', $this->legRules());
        $leg = $this->findLeg($request, $data['relationships']['tripLeg']['data']['id']);
        $user = $request->user()->workerModel();

        if (! $user || ! $trips->expectedPassengers($leg->trip)->contains('id', $user->id)) {
            throw new JsonApiException(422, 'NOT_A_PASSENGER', 'No es pasajero', 'No eres pasajero esperado de este viaje.');
        }

        $pass = $boardings->issuePass($leg, $user);

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'boarding-passes',
            'id' => $leg->id.'-'.$user->id,
            'attributes' => ['token' => $pass['token'], 'expiresAt' => $pass['expiresAt']->toIso8601String()],
            'relationships' => [
                'tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => (string) $leg->id]],
                'worker' => ['data' => ['type' => 'workers', 'id' => (string) $user->id]],
            ],
        ]), 201);
    }
}
