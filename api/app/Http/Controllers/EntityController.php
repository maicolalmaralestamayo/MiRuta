<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use App\Services\Access;
use App\Services\Organization;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Entidades. Las ve quien pertenece a ellas (el Administrador, todas); solo el
 * Administrador las crea, edita y elimina.
 */
class EntityController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'abbreviation' => 'abbreviation', 'name' => 'name', 'createdAt' => 'created_at'];

    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['search', 'active'], [], 'abbreviation');
        $query = $this->visible($request);

        if ($search = $parameters->filter('search')) {
            $like = '%'.$search.'%';
            $query->where(fn ($q) => $q->where('abbreviation', 'like', $like)->orWhere('name', 'like', $like));
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request)->findOrFail($id));
    }

    /**
     * Comprobar una abreviatura para solicitar entrar (nunca se muestra la lista
     * de Entidades): filter[abbreviation]. Con sesión o desde una instalación.
     */
    public function lookup(Request $request)
    {
        $abbreviation = trim((string) $request->input('filter.abbreviation', ''));

        if ($abbreviation === '') {
            throw JsonApiException::badRequest('Indique filter[abbreviation].', 'filter[abbreviation]');
        }

        $entity = Entity::findByAbbreviation($abbreviation);

        if (! $entity || ! $entity->active) {
            throw new JsonApiException(404, 'ENTITY_NOT_FOUND', 'Entidad no encontrada', 'No hay ninguna Entidad con esa abreviatura.');
        }

        return JsonApiResponse::make(Document::fromArray([
            'type' => 'entity-lookups',
            'id' => (string) $entity->id,
            'attributes' => ['abbreviation' => $entity->abbreviation, 'name' => $entity->name],
        ]));
    }

    public function store(Request $request)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador crea Entidades.');
        $data = $this->validateResource($request, 'entities', $this->rules(null));
        $entity = new Entity();
        $this->fill($entity, $data['attributes']);
        $entity->save();

        return $this->created($request, $entity->fresh(), 'entities');
    }

    public function update(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador edita Entidades.');
        $entity = Entity::findOrFail($id);
        $data = $this->validateResource($request, 'entities', $this->rules($entity));
        $this->fill($entity, $data['attributes'] ?? []);
        $entity->save();

        return $this->respond($request, $entity->fresh());
    }

    /**
     * Elimina la Entidad con sus itinerarios (y sus viajes y solicitudes). Las
     * personas no se eliminan: quedan sin esa Entidad.
     */
    public function destroy(Request $request, Organization $organization, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador elimina Entidades.');
        $organization->deleteEntity(Entity::findOrFail($id));

        return $this->noContent();
    }

    private function rules(?Entity $entity): array
    {
        $presence = $entity ? 'sometimes' : 'required';

        return [
            'attributes' => [$entity ? 'sometimes' : 'required', 'array'],
            'attributes.abbreviation' => [$presence, 'string', 'max:15', 'regex:/^[A-Za-z0-9ÁÉÍÓÚÑáéíóúñ._-]+$/u',
                Rule::unique('entities', 'abbreviation')->ignore($entity?->id)],
            'attributes.name' => [$presence, 'string', 'max:150', 'regex:/\S/'],
            'attributes.number' => ['sometimes', 'nullable', 'regex:/^\d{4}$/', Rule::unique('entities', 'number')->ignore($entity?->id)],
            'attributes.description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.active' => ['sometimes', 'boolean'],
        ];
    }

    private function fill(Entity $entity, array $attributes): void
    {
        if (isset($attributes['abbreviation'])) {
            $entity->abbreviation = mb_strtoupper(trim($attributes['abbreviation']));
        }

        foreach (['name' => 'name', 'number' => 'number', 'description' => 'description', 'observation' => 'observation'] as $attribute => $column) {
            if (array_key_exists($attribute, $attributes)) {
                $entity->{$column} = $attribute === 'name' ? trim($attributes[$attribute]) : self::text($attributes[$attribute]);
            }
        }

        if (array_key_exists('active', $attributes)) {
            $entity->active = (bool) $attributes['active'];
        }
    }

    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $ids = $this->access->visibleEntityIds($user);
        $query = Entity::query();

        if ($ids !== null) {
            $query->whereIn('id', $ids ?: [0]);

            if (! $this->access->seesInactive($user)) {
                $query->where('active', true);
            }
        }

        return $query;
    }
}
