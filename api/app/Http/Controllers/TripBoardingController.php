<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripBoarding;
use App\Models\User;
use App\Models\Worker;
use App\Services\Boardings;
use App\Services\QrScans;
use App\Services\Tracking;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Registro de subida: "Ya subí" (self), QR, manual. La automática la genera
 * el servidor. Una sola subida por persona y trayecto, con los hijos que
 * suben (childIds). Corregir (PATCH/DELETE): tracking.fix_passengers.
 */
class TripBoardingController extends TrackingController
{
    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['boardedAt' => 'boarded_at'], ['tripLeg', 'worker', 'outsider'], ['worker', 'worker.user', 'markedBy'], 'boardedAt');
        $query = TripBoarding::whereIn('trip_leg_id', $this->visibleLegs($request)->select('id'));

        if ($leg = $parameters->filter('tripLeg')) {
            $query->where('trip_leg_id', $leg);
        }

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        if ($outsider = $parameters->filter('outsider')) {
            $outsider === 'true' ? $query->whereNotNull('outsider') : $query->where('outsider', $outsider);
        }

        $paginator = $parameters->applySort($query, ['boardedAt' => 'boarded_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    /**
     * También sirve para sincronizar subidas escaneadas sin conexión (qr +
     * scannedAt): si el mismo código ya registró esta subida, responde 200
     * con meta.repeated = true.
     */
    public function store(Request $request, Boardings $boardings, Tracking $tracking, QrScans $scans)
    {
        $data = $this->validateResource($request, 'trip-boardings', array_merge([
            'attributes.method' => ['required', 'in:self,qr,manual'],
            'attributes.qr' => ['required_if:data.attributes.method,qr', 'string', 'max:2000'],
            'attributes.scannedAt' => ['sometimes', 'nullable', 'date'],
            'attributes.childIds' => ['sometimes', 'nullable', 'array', 'max:20'],
            'attributes.childIds.*' => ['integer'],
            'attributes.allowOutsider' => ['sometimes', 'boolean'],
            'relationships.worker.data.id' => ['required_if:data.attributes.method,manual', 'integer'],
        ], $this->legRules()));

        $user = $request->user();
        $leg = $this->findLeg($request, $data['relationships']['tripLeg']['data']['id']);
        $attributes = $data['attributes'];
        $childIds = array_key_exists('childIds', $attributes) && $attributes['childIds'] !== null ? $attributes['childIds'] : null;
        $allowOutsider = ! empty($attributes['allowOutsider']);
        $scannedAt = ! empty($attributes['scannedAt']) ? Carbon::parse($attributes['scannedAt'])->setTimezone(config('app.timezone')) : null;

        switch ($attributes['method']) {
            case TripBoarding::METHOD_SELF:
                $result = $boardings->register($leg, $user, TripBoarding::METHOD_SELF, ['childIds' => $childIds, 'at' => $scannedAt]);
                break;
            case TripBoarding::METHOD_QR:
                $result = $scans->board($leg, $attributes['qr'], $user, $scannedAt, $childIds, $allowOutsider);
                break;
            default:
                $scans->ensureCanScan($leg, $user);
                $worker = Worker::withTrashed()->find($data['relationships']['worker']['data']['id']);
                $person = $worker ? User::find($worker->user_id) : null;

                if (! $person || $worker->trashed()) {
                    throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El trabajador no existe.', ['pointer' => '/data/relationships/worker']);
                }

                $result = $boardings->register($leg, $person, TripBoarding::METHOD_MANUAL, [
                    'scanner' => $user, 'childIds' => $childIds, 'allowOutsider' => $allowOutsider, 'at' => $scannedAt,
                ]);
        }

        $document = (new Document($request))->resource($result['boarding']);

        if (! empty($result['repeated'])) {
            $document['meta'] = ['repeated' => true];
        }

        return JsonApiResponse::make($document, $result['created'] ? 201 : 200);
    }

    /**
     * Cambiar los hijos que subieron: tracking.fix_passengers; mientras el
     * trayecto está en curso, también quien puede escanear y la propia persona.
     */
    public function update(Request $request, Boardings $boardings, Tracking $tracking, $id)
    {
        $boarding = $this->findBoarding($request, $id);
        $data = $this->validateResource($request, 'trip-boardings', [
            'attributes.childIds' => ['present', 'array', 'max:20'],
            'attributes.childIds.*' => ['integer'],
        ]);
        $user = $request->user();
        $leg = $boarding->tripLeg;
        $person = User::withTrashed()->find($boarding->worker->user_id);
        $own = (int) $person->id === (int) $user->id;

        if (! $boardings->canFixPassengers($leg->trip, $user)
            && ! ($leg->isActive() && ($own || $tracking->canScan($leg->trip, $user)))) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tiene permiso para corregir los pasajeros de este viaje.');
        }

        \Illuminate\Support\Facades\DB::transaction(function () use ($boardings, $boarding, $person, $data) {
            $boardings->setChildren($boarding, $person, $data['attributes']['childIds']);
        });

        return JsonApiResponse::make((new Document($request))->resource($boarding->fresh()));
    }

    /**
     * Quitar una subida registrada por error (tracking.fix_passengers).
     */
    public function destroy(Request $request, Boardings $boardings, $id)
    {
        $boarding = $this->findBoarding($request, $id);

        if (! $boardings->canFixPassengers($boarding->tripLeg->trip, $request->user())) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tiene permiso para corregir los pasajeros de este viaje.');
        }

        $boardings->remove($boarding);

        return response('', 204);
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->findBoarding($request, $id), QueryParameters::readIncludes($request, ['worker', 'worker.user', 'markedBy'])));
    }

    private function findBoarding(Request $request, $id): TripBoarding
    {
        $boarding = TripBoarding::whereIn('trip_leg_id', $this->visibleLegs($request)->select('id'))->find($id);

        if (! $boarding) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La subida no existe o no puede verla.');
        }

        return $boarding;
    }
}
