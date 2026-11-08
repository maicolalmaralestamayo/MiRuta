<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Itinerary;
use App\Services\Access;
use App\Services\Organization;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Itinerarios de una Entidad. Los ve quien pertenece a la Entidad; solo el
 * Administrador los crea, edita y elimina. El orden de sus paradas lo cambian
 * el Administrador y sus Jefes (PATCH itineraries/{id}/relationships/stops).
 */
class ItineraryController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'name' => 'name', 'createdAt' => 'created_at'];
    public const INCLUDABLE = ['entity'];

    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['entity', 'search', 'active'], self::INCLUDABLE, 'name');
        $query = $this->visible($request);

        if ($entity = $parameters->filter('entity')) {
            $query->where('entity_id', (int) $entity);
        }

        if ($search = $parameters->filter('search')) {
            $query->where('name', 'like', '%'.$search.'%');
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request)->findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    public function store(Request $request)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador crea itinerarios.');
        $data = $this->validateResource($request, 'itineraries', $this->rules(null) + $this->relationshipRules('entity', 'entities', 'entities', true));
        $itinerary = new Itinerary(['entity_id' => $this->relationshipId($data, 'entity')]);
        $this->ensureUniqueName($itinerary->entity_id, $data['attributes']['name'], null);
        $this->fill($itinerary, $data['attributes']);
        $itinerary->save();

        return $this->created($request, $itinerary->fresh(), 'itineraries');
    }

    /**
     * Datos del itinerario y, con relationships.entity, «Cambiar de Entidad»
     * (sus personas quedan sin itinerario en la Entidad anterior).
     */
    public function update(Request $request, Organization $organization, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador edita itinerarios.');
        $itinerary = Itinerary::findOrFail($id);
        $data = $this->validateResource($request, 'itineraries', $this->rules($itinerary) + $this->relationshipRules('entity', 'entities', 'entities', false));
        $attributes = $data['attributes'] ?? [];
        $entityId = $this->relationshipId($data, 'entity') ?? $itinerary->entity_id;

        if (isset($attributes['name']) || $entityId !== $itinerary->entity_id) {
            $this->ensureUniqueName($entityId, $attributes['name'] ?? $itinerary->name, $itinerary->id);
        }

        if ($entityId !== $itinerary->entity_id) {
            \App\Models\Worker::where('itinerary_id', $itinerary->id)->update(['itinerary_id' => null, 'stop_id' => null, 'is_chief' => false]);
            $itinerary->entity_id = $entityId;
            $this->access->flush();
        }

        $this->fill($itinerary, $attributes);
        $itinerary->save();

        return $this->respond($request, $itinerary->fresh());
    }

    /**
     * Elimina el itinerario (con sus viajes y solicitudes); sus personas quedan
     * sin itinerario ni parada; las paradas se conservan.
     */
    public function destroy(Request $request, Organization $organization, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador elimina itinerarios.');
        $organization->deleteItinerary(Itinerary::findOrFail($id));

        return $this->noContent();
    }

    /**
     * PATCH itineraries/{id}/relationships/stops: nuevo orden de todas sus
     * paradas (data = [{type: stops, id}, …], de la primera a la última).
     */
    public function reorderStops(Request $request, Organization $organization, $id)
    {
        $itinerary = Itinerary::findOrFail($id);
        $this->access->requireItineraryManager($request->user(), $itinerary->id, 'Solo el Administrador o el Jefe del itinerario ordenan sus paradas.');
        $data = $request->json('data');

        if (! is_array($data) || ! array_is_list($data)) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Petición incorrecta', '"data" debe ser la lista de paradas en orden.', ['pointer' => '/data']);
        }

        $ids = [];

        foreach ($data as $index => $identifier) {
            if (! is_array($identifier) || ($identifier['type'] ?? null) !== 'stops' || ! isset($identifier['id'])) {
                throw JsonApiException::conflict('TYPE_MISMATCH', 'Cada elemento debe ser {"type": "stops", "id": …}.', '/data/'.$index);
            }
            $ids[] = (int) $identifier['id'];
        }

        $organization->reorder($itinerary, $ids);

        return \App\JsonApi\JsonApiResponse::make(['data' => array_map(fn ($id) => ['type' => 'stops', 'id' => (string) $id], $itinerary->stopIds())]);
    }

    private function rules(?Itinerary $itinerary): array
    {
        $presence = $itinerary ? 'sometimes' : 'required';

        return [
            'attributes' => [$itinerary ? 'sometimes' : 'required', 'array'],
            'attributes.name' => [$presence, 'string', 'max:100', 'regex:/\S/'],
            'attributes.description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.active' => ['sometimes', 'boolean'],
        ];
    }

    private function fill(Itinerary $itinerary, array $attributes): void
    {
        if (isset($attributes['name'])) {
            $itinerary->name = trim($attributes['name']);
        }

        foreach (['description', 'observation'] as $field) {
            if (array_key_exists($field, $attributes)) {
                $itinerary->{$field} = self::text($attributes[$field]);
            }
        }

        if (array_key_exists('active', $attributes)) {
            $itinerary->active = (bool) $attributes['active'];
        }
    }

    private function ensureUniqueName(int $entityId, string $name, ?int $exceptId): void
    {
        $exists = Itinerary::where('entity_id', $entityId)->where('name', trim($name))->when($exceptId, fn ($q) => $q->where('id', '<>', $exceptId))->exists();

        if ($exists) {
            throw JsonApiException::conflict('ITINERARY_NAME_TAKEN', 'Ya hay un itinerario con ese nombre en la Entidad.', '/data/attributes/name');
        }
    }

    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = Itinerary::query();
        $ids = $this->access->visibleEntityIds($user);

        if ($ids !== null) {
            $chiefOf = $this->access->chiefItineraryId($user);
            $query->whereIn('entity_id', $ids ?: [0])
                ->where(fn ($q) => $q->where('active', true)->when($chiefOf !== null, fn ($q) => $q->orWhere('id', $chiefOf)));
        }

        return $query;
    }
}
