<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Services\Access;
use App\Services\Nomenclators;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

/**
 * Nomencladores (docs/11 §11.26, §11.29 y §11.31). Todos los consultan (los
 * desactivados solo el Administrador); solo el Administrador los cambia. Lo que
 * está en uso no se elimina: 409 NOMENCLATOR_IN_USE propone desactivarlo.
 */
abstract class NomenclatorController extends Controller
{
    /** Tipo JSON:API (clave de Nomenclators::TYPES). */
    protected string $type;

    public const SORTABLE = ['id' => 'id', 'name' => 'name', 'createdAt' => 'created_at'];

    public function __construct(protected Access $access, protected Nomenclators $nomenclators)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['active', 'search', 'applicationType'], [], 'name');
        $query = $this->model()::query();

        if (! $this->access->isAdmin($request->user())) {
            $query->where('active', true);
        } elseif ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        if ($search = $parameters->filter('search')) {
            $query->where('name', 'like', '%'.$search.'%');
        }

        if ($this->type === 'denial-reasons' && ($type = $parameters->filter('applicationType'))) {
            $query->where(fn ($q) => $q->whereNull('application_type')->orWhere('application_type', $type));
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->model()::findOrFail($id));
    }

    public function store(Request $request)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador gestiona los nomencladores.');
        $data = $this->validateResource($request, $this->type, $this->rules(null));
        $class = $this->model();
        $item = new $class();
        $this->fill($item, $data['attributes']);
        $item->save();

        return $this->created($request, $item->fresh(), $this->type);
    }

    public function update(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador gestiona los nomencladores.');
        $item = $this->model()::findOrFail($id);
        $data = $this->validateResource($request, $this->type, $this->rules($item->id));
        $this->fill($item, $data['attributes'] ?? []);
        $item->save();

        return $this->respond($request, $item->fresh());
    }

    public function destroy(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador gestiona los nomencladores.');
        $item = $this->model()::findOrFail($id);
        $uses = $this->nomenclators->usageCount($this->type, (int) $item->id);

        if ($uses > 0) {
            throw JsonApiException::conflict('NOMENCLATOR_IN_USE',
                '«'.$item->name.'» está en uso ('.$uses.' '.($uses === 1 ? 'vez' : 'veces').') y no se puede eliminar. Desactívelo para que no se pueda elegir más.',
                null, ['usageCount' => $uses]);
        }

        $item->delete();

        return $this->noContent();
    }

    protected function model(): string
    {
        return Nomenclators::TYPES[$this->type][0];
    }

    protected function rules(?int $id): array
    {
        $presence = $id === null ? 'required' : 'sometimes';
        $table = (new ($this->model()))->getTable();
        $rules = [
            'attributes' => [$presence, 'array'],
            'attributes.name' => [$presence, 'string', 'max:100', 'regex:/\S/', Rule::unique($table, 'name')->ignore($id)],
            'attributes.description' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.observation' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'attributes.active' => ['sometimes', 'boolean'],
        ];

        if ($this->type === 'vehicle-types') {
            $rules['attributes.seats'] = [$presence, 'integer', 'min:0', 'max:500'];
            $rules['attributes.standing'] = ['sometimes', 'integer', 'min:0', 'max:500'];
        }

        if ($this->type === 'denial-reasons') {
            $rules['attributes.applicationType'] = ['sometimes', 'nullable', 'in:entidad,itinerario'];
        }

        return $rules;
    }

    protected function fill($item, array $attributes): void
    {
        foreach (['name', 'description', 'observation'] as $field) {
            if (array_key_exists($field, $attributes)) {
                $item->{$field} = self::text($attributes[$field]);
            }
        }

        if (array_key_exists('active', $attributes)) {
            $item->active = (bool) $attributes['active'];
        }

        foreach (['seats' => 'seats', 'standing' => 'standing', 'applicationType' => 'application_type'] as $attribute => $column) {
            if (array_key_exists($attribute, $attributes) && in_array($column, $item->getFillable(), true)) {
                $item->{$column} = $attributes[$attribute];
            }
        }
    }
}
