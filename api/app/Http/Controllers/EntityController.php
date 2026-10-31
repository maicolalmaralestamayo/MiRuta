<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Entidades. Solo el Administrador las lista, crea, edita y desactiva; los
 * demás solo ven la suya. Para unirse a una se busca por su abreviatura
 * exacta (lookup), sin mostrar la lista.
 */
class EntityController extends ResourceController
{
    protected $model = Entity::class;

    protected $type = 'entities';

    protected $attributes = [
        'abbreviation' => 'abbreviation',
        'number' => 'number',
        'name' => 'name',
        'description' => 'description',
        'observation' => 'observation',
    ];

    protected $sortable = ['id' => 'id', 'abbreviation' => 'abbreviation', 'name' => 'name'];

    protected $filterable = ['search', 'active'];

    protected $defaultSort = 'abbreviation';

    protected function rules(Request $request, ?Model $model): array
    {
        $presence = $model ? 'sometimes' : 'required';
        $ignore = $model ? $model->id : null;

        return [
            'attributes.abbreviation' => [$presence, 'string', 'regex:/^[A-Za-z0-9]{2,15}$/',
                Rule::unique('entities', 'abbreviation')->ignore($ignore)],
            'attributes.number' => ['sometimes', 'nullable', 'string', 'regex:/^\d{4}$/',
                Rule::unique('entities', 'number')->ignore($ignore)],
            'attributes.name' => [$presence, 'string', 'max:150'],
            'attributes.description' => ['sometimes', 'nullable', 'string'],
            'attributes.observation' => ['sometimes', 'nullable', 'string'],
        ];
    }

    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        parent::beforeSave($model, $request, $creating);
        $model->abbreviation = Entity::normalizeAbbreviation($model->abbreviation);

        if ($model->number === '') {
            $model->number = null;
        }
    }

    protected function newQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Entity::query();

        if ($user->isAdmin()) {
            $active = $request->input('filter.active');

            if ($active === 'false') {
                $query->onlyTrashed();
            } elseif ($active === 'all') {
                $query->withTrashed();
            }

            return $query;
        }

        return $query->whereKey($user->entityId());
    }

    protected function findOrFail(Request $request, $id): Model
    {
        return $request->user()->isAdmin() && $request->getMethod() !== 'GET'
            ? Entity::withTrashed()->findOrFail($id)
            : parent::findOrFail($request, $id);
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                $query->where('abbreviation', 'like', '%'.$search.'%')->orWhere('name', 'like', '%'.$search.'%');
            });
        }
    }

    /**
     * Reactivar: PATCH con attributes.active = true (o desactivar con false).
     */
    public function update(Request $request, $id)
    {
        if ($request->has('data.attributes.active')) {
            $entity = Entity::withTrashed()->findOrFail($id);
            $this->authorize('update', $entity);
            $active = filter_var($request->input('data.attributes.active'), FILTER_VALIDATE_BOOLEAN);
            $active ? $entity->restore() : $entity->delete();

            return JsonApiResponse::make((new Document($request))->resource(Entity::withTrashed()->find($entity->id)));
        }

        return parent::update($request, $id);
    }

    /**
     * Busca una Entidad activa por su abreviatura exacta (sin distinguir
     * mayúsculas). Con sesión o con instalación.
     */
    public function lookup(Request $request)
    {
        $entity = Entity::findByAbbreviation((string) $request->query('abbreviation', ''));

        if (! $entity) {
            throw new JsonApiException(404, 'ENTITY_NOT_FOUND', 'Entidad no encontrada',
                'No hay ninguna Entidad con esa abreviatura. Pregúntala a tu superior.');
        }

        return JsonApiResponse::make(['data' => [
            'type' => 'entities',
            'id' => (string) $entity->id,
            'attributes' => ['abbreviation' => $entity->abbreviation, 'name' => $entity->name],
        ]]);
    }
}
