<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Models\Application;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\User;
use App\Models\Worker;
use App\Services\Access;
use App\Services\Nomenclators;
use Illuminate\Http\Request;

/**
 * GET management-summary: las cantidades de las tarjetas de Gestión (docs/11
 * §11.59): Entidades, Itinerarios, Paradas y Trabajadores que ve quien
 * consulta, con las solicitudes pendientes que le toca resolver, y (solo el
 * Administrador) los elementos de cada nomenclador.
 */
class ManagementSummaryController extends Controller
{
    public function __construct(private Access $access)
    {
    }

    public function show(Request $request)
    {
        $user = $request->user();
        $admin = $this->access->isAdmin($user);
        $entityIds = $this->access->entityIds($user) ?: [0];
        $chiefOf = $this->access->chiefItineraryId($user);

        $entities = $admin ? Entity::count()
            : Entity::whereIn('id', $entityIds)->when(! $this->access->seesInactive($user), fn ($q) => $q->where('active', true))->count();
        $itineraries = $admin ? Itinerary::count()
            : Itinerary::whereIn('entity_id', $entityIds)->where(fn ($q) => $q->where('active', true)->when($chiefOf !== null, fn ($q) => $q->orWhere('id', $chiefOf)))->count();
        $stops = $admin || $chiefOf !== null ? Stop::count()
            : Stop::where('active', true)->whereIn('id', ItineraryStop::whereIn('itinerary_id', Itinerary::whereIn('entity_id', $entityIds)->select('id'))->select('stop_id'))->count();
        $workers = $admin ? User::count()
            : User::where(fn ($q) => $q->where('id', $user->id)->orWhereIn('id', Worker::whereIn('entity_id', $entityIds)->select('user_id')))->count();

        $pendingEntity = $admin ? Application::where('status', Application::PENDING)->where('type', Application::TYPE_ENTITY)->count() : 0;
        $pendingItinerary = $admin
            ? Application::where('status', Application::PENDING)->where('type', Application::TYPE_ITINERARY)->count()
            : ($chiefOf === null ? 0 : Application::where('status', Application::PENDING)->where('type', Application::TYPE_ITINERARY)->where('itinerary_id', $chiefOf)->count());

        $nomenclators = [];

        if ($admin) {
            foreach (Nomenclators::TYPES as $type => [$class]) {
                $nomenclators[$type] = $class::count();
            }
        }

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'management-summaries',
            'id' => (string) $user->id,
            'attributes' => [
                'entities' => $entities,
                'itineraries' => $itineraries,
                'stops' => $stops,
                'workers' => $workers,
                'pendingEntityApplications' => $pendingEntity,
                'pendingItineraryApplications' => $pendingItinerary,
                'nomenclators' => (object) $nomenclators,
            ],
        ]));
    }
}
