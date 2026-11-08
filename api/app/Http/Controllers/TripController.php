<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Trip;
use App\Models\TripPassenger;
use App\Models\Worker;
use App\Services\Access;
use App\Services\Trips;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Viajes (docs/11 §11.33, §11.43, §11.47 y §11.53). Cada viaje es de ida o de
 * regreso; se planifican a mano, uno a uno.
 *
 * - Secciones de la pestaña Viajes: filter[status]=planificado, en_ejecucion,
 *   terminado o cancelado (lista separada por comas).
 * - PATCH: datos (solo Planificado) y attributes.status para cambiar de estado
 *   a mano; relationships.detentionCause: causa de la detención.
 * - GET trips/{id}/live: la línea del recorrido.
 * - POST trips/{id}/reports: informe del teléfono (estado del trabajador y,
 *   si es sensor, del vehículo); responde con la línea del recorrido.
 */
class TripController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'departsAt' => 'departs_at', 'createdAt' => 'created_at', 'updatedAt' => 'updated_at'];
    public const INCLUDABLE = ['itinerary', 'vehicleType', 'detentionCause', 'createdBy'];

    public function __construct(private Trips $trips, private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['status', 'itinerary', 'direction', 'date', 'from', 'to'], self::INCLUDABLE, 'departsAt');
        $query = $this->trips->visibleQuery($request->user());

        if ($status = $parameters->filter('status')) {
            $query->whereIn('status', explode(',', $status));
        }

        foreach (['itinerary' => 'itinerary_id', 'direction' => 'direction', 'date' => 'date'] as $filter => $column) {
            if (($value = $parameters->filter($filter)) !== null) {
                $query->where($column, $value);
            }
        }

        if ($from = $parameters->filter('from')) {
            $query->where('date', '>=', $from);
        }

        if ($to = $parameters->filter('to')) {
            $query->where('date', '<=', $to);
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->find($request, $id), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    /**
     * Planifica un viaje: itinerario, sentido (ida o regreso), fecha, hora y
     * tipo de vehículo. Para la ida y el regreso del mismo día, dos peticiones.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'trips', [
            'attributes.direction' => ['required', 'in:ida,regreso'],
            'attributes.date' => ['required', 'date_format:Y-m-d'],
            'attributes.departureTime' => ['required', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
            'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:1000'],
        ] + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', true)
          + $this->relationshipRules('vehicleType', 'vehicle-types', 'vehicle_types', true));
        $attributes = $data['attributes'];
        $trip = $this->trips->create($request->user(), $this->relationshipId($data, 'itinerary'), $attributes['direction'],
            $attributes['date'], $attributes['departureTime'], $this->relationshipId($data, 'vehicleType'), self::text($attributes['observation'] ?? null));

        return $this->created($request, $trip->fresh(), 'trips');
    }

    public function update(Request $request, $id)
    {
        $trip = $this->find($request, $id);
        $data = $this->validateResource($request, 'trips', [
            'attributes.date' => ['sometimes', 'date_format:Y-m-d'],
            'attributes.departureTime' => ['sometimes', 'regex:/^([01]\d|2[0-3]):[0-5]\d$/'],
            'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'attributes.status' => ['sometimes', 'in:planificado,en_ejecucion,terminado,cancelado'],
        ] + $this->relationshipRules('vehicleType', 'vehicle-types', 'vehicle_types', false)
          + $this->relationshipRules('detentionCause', 'detention-causes', 'detention_causes', false, true));
        $attributes = $data['attributes'] ?? [];
        $user = $request->user();

        DB::transaction(function () use ($trip, $attributes, $data, $user) {
            $changes = array_intersect_key($attributes, array_flip(['date', 'departureTime', 'observation']));

            if (array_key_exists('observation', $changes)) {
                $changes['observation'] = self::text($changes['observation']);
            }

            if ($this->relationshipId($data, 'vehicleType') !== null) {
                $changes['vehicleTypeId'] = $this->relationshipId($data, 'vehicleType');
            }

            if ($changes) {
                $this->trips->update($user, $trip, $changes);
            }

            if ($this->hasRelationship($data, 'detentionCause')) {
                $this->trips->setDetentionCause($user, $trip, $this->relationshipId($data, 'detentionCause'));
            }

            if (isset($attributes['status'])) {
                $this->trips->changeStatus($user, $trip, $attributes['status']);
            }
        });

        return $this->respond($request, $trip->fresh(), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    /**
     * Eliminar: el Administrador o el Jefe del itinerario, si no está en ejecución.
     */
    public function destroy(Request $request, $id)
    {
        $trip = $this->find($request, $id);
        $this->access->requireItineraryManager($request->user(), $trip->itinerary_id, 'Solo el Administrador o el Jefe del itinerario eliminan sus viajes.');

        if ($trip->status === Trip::RUNNING) {
            throw JsonApiException::conflict('TRIP_RUNNING', 'Un viaje en ejecución no se elimina: termínelo primero.');
        }

        $trip->delete();

        return $this->noContent();
    }

    public function live(Request $request, $id)
    {
        $trip = $this->find($request, $id);

        return JsonApiResponse::make(Document::fromArray($this->trips->live($trip, $request->user())));
    }

    /**
     * «Trabajadores» del viaje: los esperados y quienes informaron, con su estado.
     */
    public function passengers(Request $request, $id)
    {
        $trip = $this->find($request, $id);
        $states = TripPassenger::where('trip_id', $trip->id)->get()->keyBy('user_id');
        $expected = $this->trips->expectedQuery($trip)->with('user')->get();
        $userIds = $expected->pluck('user_id')->merge($states->keys())->unique();
        $workers = Worker::where('itinerary_id', $trip->itinerary_id)->whereIn('user_id', $userIds)->with('user')->get()->keyBy('user_id');
        $rows = [];

        foreach ($userIds as $userId) {
            $worker = $workers[$userId] ?? null;
            $state = $states[$userId] ?? null;
            $rows[] = [
                'type' => 'trip-workers',
                'id' => $trip->id.'-'.$userId,
                'attributes' => [
                    'fullName' => $worker?->user?->fullName(),
                    'photoUrl' => $worker?->user?->photo_path ? url($worker->user->photo_path) : null,
                    'expected' => $expected->contains('user_id', $userId),
                    'state' => $state?->state,
                    'stateAt' => $state?->state_at?->toIso8601String(),
                    'childrenCount' => (int) ($state?->children_count ?? 0),
                    'isChief' => (bool) $worker?->is_chief,
                ],
                'relationships' => [
                    'user' => ['data' => ['type' => 'users', 'id' => (string) $userId]],
                    'stop' => ['data' => ($state?->stop_id ?? $worker?->stop_id) ? ['type' => 'stops', 'id' => (string) ($state?->stop_id ?? $worker?->stop_id)] : null],
                ],
            ];
        }

        usort($rows, fn ($a, $b) => strcmp((string) $a['attributes']['fullName'], (string) $b['attributes']['fullName']));

        return JsonApiResponse::make(Document::fromArray($rows, ['total' => count($rows)]));
    }

    /**
     * Informe del teléfono (con acuse). attributes: workerState, stopId (Dejado
     * en otra parada), childIds o childrenCount, vehicleState (detenido o
     * en_movimiento), atStop, nextStopIndex y reportedAt (hora del teléfono).
     */
    public function report(Request $request, $id)
    {
        $trip = $this->find($request, $id);
        $data = $this->validateResource($request, 'trip-reports', [
            'attributes' => ['required', 'array'],
            'attributes.workerState' => ['sometimes', 'string'],
            'attributes.stopId' => ['sometimes', 'nullable', 'integer'],
            'attributes.childIds' => ['sometimes', 'array', 'max:20'],
            'attributes.childIds.*' => ['integer'],
            'attributes.childrenCount' => ['sometimes', 'integer', 'min:0', 'max:20'],
            'attributes.vehicleState' => ['sometimes', 'in:detenido,en_movimiento'],
            'attributes.atStop' => ['sometimes', 'boolean'],
            'attributes.nextStopIndex' => ['sometimes', 'integer', 'min:0'],
            'attributes.reportedAt' => ['sometimes', 'date'],
        ]);
        $ack = $this->trips->report($request->user(), $trip, $data['attributes']);
        $live = $this->trips->live($trip->fresh(), $request->user());

        return JsonApiResponse::make(Document::fromArray($live, ['ack' => true] + $ack));
    }

    private function find(Request $request, $id): Trip
    {
        return $this->trips->visibleQuery($request->user())->findOrFail($id);
    }
}
