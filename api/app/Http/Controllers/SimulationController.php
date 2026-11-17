<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Models\Itinerary;
use App\Models\Simulation;
use App\Services\Access;
use App\Services\Simulations;
use Illuminate\Http\Request;

/**
 * Simulador de trabajadores (docs/11 §11.66), solo para el Administrador
 * (Más → Mantenimiento del servidor → Simulación). Una sola simulación a la
 * vez. Cada consulta la hace avanzar hasta ahora.
 *
 * - GET simulations: la simulación (0 o 1), con su estado.
 * - POST simulations: «Crear Simulación».
 * - GET simulations/{id}: su estado.
 * - DELETE simulations/{id}: «Eliminar Simulación» (lo borra todo).
 */
class SimulationController extends Controller
{
    public function __construct(private Simulations $simulations, private Access $access)
    {
    }

    public function index(Request $request)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador usa el simulador.');
        $this->simulations->advance(true);
        $current = $this->simulations->current();

        return JsonApiResponse::make(Document::fromArray($current ? [$this->resource($current)] : [], ['total' => $current ? 1 : 0]));
    }

    public function show(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador usa el simulador.');
        $this->simulations->advance(true);

        return JsonApiResponse::make(Document::fromArray($this->resource(Simulation::findOrFail($id))));
    }

    public function store(Request $request)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador usa el simulador.');
        $data = $this->validateResource($request, 'simulations', [
            'attributes.direction' => ['sometimes', 'in:ida,regreso'],
            'attributes.workers' => ['required', 'integer', 'min:1', 'max:'.Simulations::MAX_WORKERS],
            'attributes.vehicleMode' => ['sometimes', 'in:simulado,real'],
            'attributes.normal' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'attributes.late' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'attributes.leftBehind' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'attributes.notGoing' => ['sometimes', 'integer', 'min:0', 'max:100'],
            'attributes.speedFactor' => ['sometimes', 'integer', 'in:'.implode(',', Simulations::SPEED_FACTORS)],
            'attributes.vehicleSpeed' => ['sometimes', 'integer', 'min:5', 'max:120'],
            'attributes.seed' => ['sometimes', 'nullable', 'integer', 'min:1'],
        ] + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', true)
          + $this->relationshipRules('vehicleType', 'vehicle-types', 'vehicle_types', false));
        $attributes = $data['attributes'] ?? [];
        $simulation = $this->simulations->create($request->user(), [
            'itineraryId' => $this->relationshipId($data, 'itinerary'),
            'vehicleTypeId' => $this->relationshipId($data, 'vehicleType'),
        ] + $attributes);

        return JsonApiResponse::make(Document::fromArray($this->resource($simulation)), 201, ['Location' => url('api/v1/simulations/'.$simulation->id)]);
    }

    public function destroy(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador usa el simulador.');
        $this->simulations->delete(Simulation::findOrFail($id));

        return $this->noContent();
    }

    private function resource(Simulation $simulation): array
    {
        return [
            'type' => 'simulations',
            'id' => (string) $simulation->id,
            'attributes' => [
                'itineraryName' => Itinerary::find($simulation->itinerary_id)?->name,
                'direction' => $simulation->direction,
                'vehicleMode' => $simulation->vehicle_mode,
                'workers' => $simulation->workers_count,
                'normal' => $simulation->pct_normal,
                'late' => $simulation->pct_late,
                'leftBehind' => $simulation->pct_left_behind,
                'notGoing' => $simulation->pct_not_going,
                'speedFactor' => $simulation->speed_factor,
                'vehicleSpeed' => $simulation->vehicle_speed_kmh,
                'seed' => $simulation->seed,
                'status' => $simulation->status,
                'startedAt' => $simulation->started_at?->toIso8601String(),
                'lastTickAt' => $simulation->last_tick_at?->toIso8601String(),
                'finishedAt' => $simulation->finished_at?->toIso8601String(),
            ] + $this->simulations->status($simulation),
            'relationships' => [
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $simulation->itinerary_id]],
                'trip' => ['data' => $simulation->trip_id ? ['type' => 'trips', 'id' => (string) $simulation->trip_id] : null],
                'createdBy' => ['data' => ['type' => 'users', 'id' => (string) $simulation->created_by]],
            ],
        ];
    }
}
