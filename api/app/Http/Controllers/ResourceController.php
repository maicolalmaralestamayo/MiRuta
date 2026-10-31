<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Controlador JSON:API genérico: listar, ver, crear, modificar y borrar
 * (borrado lógico), con permisos por política, filtros, orden e include.
 *
 * Cada recurso define su modelo, sus reglas de validación y cómo se pasan
 * los atributos y relaciones a columnas.
 */
abstract class ResourceController extends Controller
{
    /** @var string Clase del modelo */
    protected $model;

    /** @var string Tipo JSON:API */
    protected $type;

    /** @var array [atributo JSON:API => columna] */
    protected $attributes = [];

    /** @var array [relación JSON:API => [tipo, columna]] */
    protected $relationships = [];

    /** @var array [campo de orden => columna] */
    protected $sortable = ['id' => 'id'];

    /** @var string[] */
    protected $filterable = [];

    /** @var string[] */
    protected $includable = [];

    /** @var string|null */
    protected $defaultSort = 'id';

    /**
     * El recurso es de una Entidad (tabla raíz con entity_id): cada uno ve
     * los de la suya y los crea en la suya; el Administrador ve todos
     * (filter[entity]) y al crear indica relationships.entity.
     *
     * @var bool
     */
    protected $entityScoped = false;

    /**
     * Reglas de validación con claves JSON:API ("attributes.name").
     * $model es null al crear.
     */
    abstract protected function rules(Request $request, ?Model $model): array;

    public function index(Request $request)
    {
        $this->authorize('viewAny', $this->model);

        $parameters = QueryParameters::fromRequest($request, $this->sortable, $this->filterable, $this->includable, $this->defaultSort);
        $query = $this->newQuery($request);
        $this->applyFilters($query, $parameters, $request);

        $paginator = $parameters->applySort($query, $this->sortable)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        $model = $this->findOrFail($request, $id);
        $this->authorize('view', $model);

        return JsonApiResponse::make((new Document($request))->resource($model, QueryParameters::readIncludes($request, $this->includable)));
    }

    public function store(Request $request)
    {
        $this->authorize('create', $this->model);

        $rules = $this->rules($request, null);

        if ($this->entityScoped && $request->user()->isAdmin()) {
            $rules += $this->relationshipRules('entity', 'entities', 'entities', true);
        }

        $data = $this->validateResource($request, $this->type, $rules);

        $model = DB::transaction(function () use ($data, $request) {
            $model = $this->restorable($data) ?: new $this->model();
            $this->fill($model, $data);

            if ($this->entityScoped) {
                $model->entity_id = $request->user()->isAdmin()
                    ? (int) $data['relationships']['entity']['data']['id']
                    : $request->user()->entityId();
            }
            $this->beforeSave($model, $request, true);
            $model->save();
            $this->afterSave($model, $request, true);

            return $model;
        });

        $model = $model->fresh();

        return JsonApiResponse::make(
            (new Document($request))->resource($model, QueryParameters::readIncludes($request, $this->includable)),
            201,
            ['Location' => url('api/v1/'.$this->type.'/'.$model->getKey())]
        );
    }

    public function update(Request $request, $id)
    {
        $model = $this->findOrFail($request, $id);
        $this->authorize('update', $model);

        $data = $this->validateResource($request, $this->type, $this->rules($request, $model));

        if (isset($data['id']) && (string) $data['id'] !== (string) $model->getKey()) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        DB::transaction(function () use ($model, $data, $request) {
            $this->fill($model, $data);
            $this->beforeSave($model, $request, false);
            $model->save();
            $this->afterSave($model, $request, false);
        });

        return JsonApiResponse::make((new Document($request))->resource($model->fresh(), QueryParameters::readIncludes($request, $this->includable)));
    }

    public function destroy(Request $request, $id)
    {
        $model = $this->findOrFail($request, $id);
        $this->authorize('delete', $model);

        DB::transaction(function () use ($model, $request) {
            $this->beforeDelete($model, $request);
            $model->delete();
            $this->afterDelete($model, $request);
        });

        return response('', 204);
    }

    /**
     * Consulta base del listado y de la búsqueda por id (permite limitar lo visible).
     */
    protected function newQuery(Request $request): Builder
    {
        $query = $this->model::query();

        if ($this->entityScoped && $request->user()) {
            $query->visibleTo($request->user());

            if ($request->user()->isAdmin() && ($entity = $request->input('filter.entity'))) {
                $query->where((new $this->model())->getTable().'.entity_id', $entity);
            }
        }

        return $query;
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
    }

    protected function findOrFail(Request $request, $id): Model
    {
        return $this->newQuery($request)->findOrFail($id);
    }

    /**
     * Pasa los atributos y relaciones del documento a las columnas del modelo.
     */
    protected function fill(Model $model, array $data): void
    {
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];

        foreach ($this->attributes as $attribute => $column) {
            if (array_key_exists($attribute, $attributes)) {
                $value = $attributes[$attribute];
                $model->{$column} = is_string($value) ? trim($value) : $value;
            }
        }

        $relationships = isset($data['relationships']) ? $data['relationships'] : [];

        foreach ($this->relationships as $relationship => list($type, $column)) {
            if (array_key_exists($relationship, $relationships) && array_key_exists('data', $relationships[$relationship])) {
                $identifier = $relationships[$relationship]['data'];
                $model->{$column} = $identifier === null ? null : (int) $identifier['id'];
            }
        }
    }

    /**
     * Fila borrada lógicamente que coincide con una clave única del nuevo
     * recurso. Si se devuelve, se restaura en lugar de insertar otra.
     */
    protected function restorable(array $data): ?Model
    {
        return null;
    }

    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        if ($creating && method_exists($model, 'trashed') && $model->trashed()) {
            $model->deleted_at = null;
        }
    }

    protected function afterSave(Model $model, Request $request, bool $creating): void
    {
    }

    protected function beforeDelete(Model $model, Request $request): void
    {
    }

    protected function afterDelete(Model $model, Request $request): void
    {
    }

    /**
     * Reglas para una relación a uno: tipo correcto e id existente y no borrado.
     */
    protected function relationshipRules(string $name, string $type, string $table, bool $required, bool $nullable = false): array
    {
        $presence = $required ? 'required' : 'sometimes';

        return [
            "relationships.{$name}" => [$presence, 'array'],
            "relationships.{$name}.data" => $nullable ? ['present', 'nullable', 'array'] : [$presence, 'array'],
            "relationships.{$name}.data.type" => ["required_with:data.relationships.{$name}.data", "in:{$type}"],
            "relationships.{$name}.data.id" => ["required_with:data.relationships.{$name}.data", "exists:{$table},id,deleted_at,NULL"],
        ];
    }
}
