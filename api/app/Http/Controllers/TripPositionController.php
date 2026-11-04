<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripPosition;
use App\Services\Tracking;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TripPositionController extends TrackingController
{
    /** @var Tracking */
    private $tracking;

    public function __construct(Tracking $tracking)
    {
        $this->tracking = $tracking;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['recordedAt' => 'recorded_at'], ['tripLeg', 'since', 'worker'], [], 'recordedAt');

        if (! $parameters->filter('tripLeg')) {
            throw JsonApiException::badRequest('Hay que indicar filter[tripLeg].', 'filter[tripLeg]');
        }

        $leg = $this->findLeg($request, $parameters->filter('tripLeg'));
        $query = TripPosition::where('trip_leg_id', $leg->id);

        if ($since = $parameters->filter('since')) {
            $query->where('recorded_at', '>', Carbon::parse($since)->setTimezone(config('app.timezone')));
        }

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        $paginator = $parameters->applySort($query, ['recordedAt' => 'recorded_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator));
    }

    /**
     * Posición del usuario autenticado como sensor.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'trip-positions', $this->rules());
        $position = $this->create($data, $request);

        return JsonApiResponse::make((new Document($request))->resource($position), 201);
    }

    /**
     * Para enviar posiciones acumuladas sin conexión con /operations.
     */
    public function createFromOperation(array $data, Request $request, string $pointer)
    {
        $validator = Validator::make(['data' => $data], $this->prefixed($this->rules()));

        if ($validator->fails()) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Error de validación', $validator->errors()->first(), ['pointer' => $pointer]);
        }

        return $this->create($data, $request);
    }

    private function create(array $data, Request $request): TripPosition
    {
        $leg = $this->findLeg($request, $data['relationships']['tripLeg']['data']['id']);
        $attributes = $data['attributes'];

        $sensor = $request->user()->workerIn(app(\App\Services\Trips::class)->entityOf($leg->trip));

        if (! $sensor) {
            throw new \App\JsonApi\JsonApiException(422, 'NOT_A_SENSOR', 'Sin pertenencia', 'Solo un trabajador de la Entidad del viaje puede compartir su ubicación como sensor.');
        }

        return $this->tracking->addPosition(
            $leg,
            $sensor,
            (float) $attributes['latitude'],
            (float) $attributes['longitude'],
            isset($attributes['accuracyM']) ? (float) $attributes['accuracyM'] : null,
            Carbon::parse($attributes['recordedAt'])->setTimezone(config('app.timezone'))
        );
    }

    private function rules(): array
    {
        return array_merge([
            'attributes.latitude' => ['required', 'numeric', 'between:-90,90'],
            'attributes.longitude' => ['required', 'numeric', 'between:-180,180'],
            'attributes.accuracyM' => ['sometimes', 'nullable', 'numeric', 'min:0'],
            'attributes.recordedAt' => ['required', 'date'],
        ], $this->legRules());
    }

    private function prefixed(array $rules): array
    {
        $prefixed = [];

        foreach ($rules as $key => $value) {
            $prefixed['data.'.$key] = $value;
        }

        return $prefixed;
    }
}
