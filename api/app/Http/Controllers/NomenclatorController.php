<?php

namespace App\Http\Controllers;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use App\JsonApi\QueryParameters;
use Illuminate\Http\Request;

/**
 * Nomencladores: denominación única, descripción y observación. Crear uno con
 * la denominación de otro borrado lo restaura.
 */
abstract class NomenclatorController extends ResourceController
{
    protected $attributes = [
        'name' => 'name',
        'description' => 'description',
        'observation' => 'observation',
    ];

    protected $sortable = ['id' => 'id', 'name' => 'name'];

    protected $filterable = ['name'];

    protected $defaultSort = 'name';

    protected function rules(Request $request, ?Model $model): array
    {
        $table = (new $this->model())->getTable();
        $unique = "unique:{$table},name".($model ? ",{$model->id}" : ',NULL').',id,deleted_at,NULL';

        return [
            'attributes.name' => [$model ? 'sometimes' : 'required', 'string', 'max:100', $unique],
            'attributes.description' => ['sometimes', 'nullable', 'string'],
            'attributes.observation' => ['sometimes', 'nullable', 'string'],
        ];
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($name = $parameters->filter('name')) {
            $query->where('name', 'like', '%'.$name.'%');
        }
    }

    protected function restorable(array $data): ?Model
    {
        return $this->model::onlyTrashed()->where('name', trim($data['attributes']['name']))->first();
    }
}
