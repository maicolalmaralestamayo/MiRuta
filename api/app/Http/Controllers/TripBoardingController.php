<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripBoarding;
use App\Models\Worker;
use App\Services\Boardings;
use App\Services\Tracking;
use Illuminate\Http\Request;

/**
 * Registro de subida: "Ya subí" (self), QR, manual. La automática la genera el servidor.
 */
class TripBoardingController extends TrackingController
{
    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['boardedAt' => 'boarded_at'], ['tripLeg', 'worker'], ['worker', 'markedBy'], 'boardedAt');
        $query = TripBoarding::whereIn('trip_leg_id', $this->visibleLegs($request)->select('id'));

        if ($leg = $parameters->filter('tripLeg')) {
            $query->where('trip_leg_id', $leg);
        }

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        $paginator = $parameters->applySort($query, ['boardedAt' => 'boarded_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function store(Request $request, Boardings $boardings, Tracking $tracking)
    {
        $data = $this->validateResource($request, 'trip-boardings', array_merge([
            'attributes.method' => ['required', 'in:self,qr,manual'],
            'attributes.childrenCount' => ['sometimes', 'nullable', 'integer', 'min:0', 'max:20'],
            'attributes.boardingPassToken' => ['required_if:data.attributes.method,qr', 'string'],
            'relationships.worker.data.id' => ['required_if:data.attributes.method,manual', 'integer'],
        ], $this->legRules()));

        $user = $request->user();
        $leg = $this->findLeg($request, $data['relationships']['tripLeg']['data']['id']);
        $attributes = $data['attributes'];
        $children = isset($attributes['childrenCount']) ? (int) $attributes['childrenCount'] : null;

        switch ($attributes['method']) {
            case TripBoarding::METHOD_SELF:
                $worker = $user->workerModel();
                $markedBy = $user;

                if (! $worker) {
                    throw new JsonApiException(422, 'NOT_A_PASSENGER', 'No es pasajero', 'No eres pasajero de este viaje.');
                }
                break;
            default:
                if (! $tracking->canOperate($leg->trip, $user)) {
                    throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el chofer y los jefes pueden registrar la subida de otros.');
                }
                $worker = $attributes['method'] === TripBoarding::METHOD_QR
                    ? $boardings->verifyPass($attributes['boardingPassToken'], $leg)
                    : Worker::findOrFail($data['relationships']['worker']['data']['id']);
                $markedBy = $user;
        }

        $boarding = $boardings->board($leg, $worker, $attributes['method'], $children, $markedBy);

        return JsonApiResponse::make((new Document($request))->resource($boarding->fresh()), 201);
    }
}
