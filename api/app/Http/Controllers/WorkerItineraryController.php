<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Itinerary;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Services\Access;
use App\Services\Memberships;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * La persona en un itinerario (recurso "worker-itineraries"; docs/11 §11.58):
 * una persona puede estar en varios itinerarios de cada una de sus Entidades,
 * cada uno con su parada (opcional), y es Jefe de uno solo.
 *
 * - POST (relationships user, itinerary y stop opcional; attributes.isChief):
 *   el Administrador a cualquiera (si no estaba en la Entidad del itinerario,
 *   se le añade); el Jefe, en su itinerario, a personas de su Entidad. Si ya
 *   estaba, 409 ALREADY_IN_ITINERARY.
 * - PATCH: relationships.stop (el Administrador, el Jefe del itinerario o la
 *   propia persona) y attributes.isChief (solo el Administrador).
 * - DELETE: salir del itinerario (el Administrador, el Jefe del itinerario o
 *   la propia persona).
 * - Filtros: user, itinerary, entity, stop (id o «none» = sin parada), chief.
 */
class WorkerItineraryController extends Controller
{
    public const INCLUDABLE = ['user', 'worker', 'itinerary', 'stop'];

    public function __construct(private Access $access, private Memberships $memberships)
    {
    }

    public function index(Request $request)
    {
        $sortable = [
            'id' => 'id',
            'createdAt' => 'created_at',
            'name' => User::select('first_name')->whereColumn('users.id', 'worker_itineraries.user_id'),
            'surname' => User::select('first_surname')->whereColumn('users.id', 'worker_itineraries.user_id'),
        ];
        $parameters = QueryParameters::fromRequest($request, $sortable, ['user', 'itinerary', 'entity', 'stop', 'chief', 'search'], self::INCLUDABLE, 'name,surname');
        $query = $this->visible($request->user());

        foreach (['user' => 'user_id', 'itinerary' => 'itinerary_id'] as $filter => $column) {
            if (($value = $parameters->filter($filter)) !== null) {
                $query->where($column, (int) $value);
            }
        }

        if (($entity = $parameters->filter('entity')) !== null) {
            $query->whereIn('itinerary_id', Itinerary::where('entity_id', (int) $entity)->select('id'));
        }

        $stop = $parameters->filter('stop');

        if ($stop === 'none') {
            $query->whereNull('stop_id');
        } elseif ($stop !== null) {
            $query->where('stop_id', (int) $stop);
        }

        if ($parameters->filter('chief') !== null) {
            $query->where('is_chief', $parameters->filter('chief') === 'true');
        }

        if ($search = $parameters->filter('search')) {
            PersonController::search($query, $search, 'user_id');
        }

        return $this->paginate($request, $query, $parameters, $sortable);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request->user())->findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function store(Request $request)
    {
        $actor = $request->user();
        $data = $this->validateResource($request, 'worker-itineraries', [
            'attributes.isChief' => ['sometimes', 'boolean'],
        ] + $this->relationshipRules('user', 'users', 'users', true)
          + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', true)
          + $this->relationshipRules('stop', 'stops', 'stops', false, true));
        $user = User::findOrFail($this->relationshipId($data, 'user'));
        $itinerary = Itinerary::findOrFail($this->relationshipId($data, 'itinerary'));
        $isChief = (bool) ($data['attributes']['isChief'] ?? false);

        if (! $this->access->isAdmin($actor)) {
            $chiefOf = $this->access->chiefItineraryId($actor);
            $sameEntity = $itinerary->entity_id && Worker::where('user_id', $user->id)->where('entity_id', $itinerary->entity_id)->exists();

            if ($chiefOf !== (int) $itinerary->id || ! $sameEntity || $isChief) {
                throw Access::forbidden('Para entrar en un itinerario hay que solicitarlo (o que lo incluya su Jefe, que debe ser de su Entidad).');
            }
        }

        if (WorkerItinerary::where('user_id', $user->id)->where('itinerary_id', $itinerary->id)->exists()) {
            throw JsonApiException::conflict('ALREADY_IN_ITINERARY', 'Esa persona ya está en ese itinerario.', '/data/relationships/itinerary');
        }

        $placement = DB::transaction(function () use ($user, $itinerary, $data, $isChief) {
            $placement = $this->memberships->addItinerary($user, $itinerary, $this->relationshipId($data, 'stop'));

            return $isChief ? $this->memberships->makeChief($placement) : $placement;
        });

        return $this->created($request, $placement->fresh(), 'worker-itineraries');
    }

    public function update(Request $request, $id)
    {
        $actor = $request->user();
        $placement = $this->visible($actor)->findOrFail($id);
        $data = $this->validateResource($request, 'worker-itineraries', [
            'attributes.isChief' => ['sometimes', 'boolean'],
        ] + $this->relationshipRules('stop', 'stops', 'stops', false, true));

        if (isset($data['id']) && (string) $data['id'] !== (string) $placement->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        DB::transaction(function () use ($actor, $placement, $data) {
            if ($this->hasRelationship($data, 'stop')) {
                $this->authorizeOwnOrManager($actor, $placement, 'Solo el Administrador, el Jefe del itinerario o la propia persona cambian su parada.');
                $this->memberships->setStop($placement, $this->relationshipId($data, 'stop'));
            }

            if (array_key_exists('isChief', $data['attributes'] ?? [])) {
                $this->access->requireAdmin($actor, 'Solo el Administrador asigna y quita el rol de Jefe de itinerario.');
                $data['attributes']['isChief'] ? $this->memberships->makeChief($placement) : $this->memberships->removeChief($placement);
            }
        });

        return $this->respond($request, $placement->fresh(), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function destroy(Request $request, $id)
    {
        $actor = $request->user();
        $placement = $this->visible($actor)->findOrFail($id);
        $this->authorizeOwnOrManager($actor, $placement, 'Solo el Administrador, el Jefe del itinerario o la propia persona la sacan del itinerario.');
        $this->memberships->leaveItinerary($placement);

        return $this->noContent();
    }

    private function authorizeOwnOrManager(User $actor, WorkerItinerary $placement, string $detail): void
    {
        if ((int) $placement->user_id !== (int) $actor->id && ! $this->access->canManageItinerary($actor, $placement->itinerary_id)) {
            throw Access::forbidden($detail);
        }
    }

    /**
     * El Administrador ve todo; los demás, los itinerarios de sus Entidades.
     */
    private function visible(User $viewer): Builder
    {
        $query = WorkerItinerary::query();

        if ($this->access->isAdmin($viewer)) {
            return $query;
        }

        return $query->where(fn ($q) => $q->where('user_id', $viewer->id)
            ->orWhereIn('worker_id', Worker::whereIn('entity_id', $this->access->entityIds($viewer) ?: [0])->select('id')));
    }
}
