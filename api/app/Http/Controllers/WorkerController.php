<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Worker;
use App\Rules\CardNumberRule;
use App\Services\TokenService;
use App\Services\WorkerRegistration;
use App\Support\CardNumber;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class WorkerController extends ResourceController
{
    protected $model = Worker::class;

    protected $type = 'workers';

    protected $sortable = [
        'id' => 'id',
        'firstName' => 'first_name',
        'lastName' => 'last_name',
        'createdAt' => 'created_at',
    ];

    protected $filterable = ['itinerary', 'stop', 'rank', 'active', 'search'];

    protected $includable = ['rank', 'itinerary', 'stop'];

    protected $defaultSort = 'lastName,firstName';

    protected function rules(Request $request, ?Model $model): array
    {
        return ['attributes.active' => ['required', 'boolean']];
    }

    /**
     * Registro público. El primer trabajador registrado es Administrador.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'workers', [
            'attributes.cardNumber' => ['required', 'string', new CardNumberRule()],
            'attributes.firstName' => ['required', 'string', 'max:100'],
            'attributes.lastName' => ['required', 'string', 'max:150'],
            'attributes.password' => ['required', 'string', 'min:8', 'max:72'],
            'relationships.rank.data.type' => ['required', 'in:ranks'],
            'relationships.rank.data.id' => ['required', 'exists:ranks,id,deleted_at,NULL'],
        ]);

        $attributes = $data['attributes'];

        $worker = app(WorkerRegistration::class)->register(
            CardNumber::tryParse($attributes['cardNumber']),
            trim($attributes['firstName']),
            trim($attributes['lastName']),
            (int) $data['relationships']['rank']['data']['id'],
            $attributes['password']
        );

        return JsonApiResponse::make((new Document($request))->resource($worker->fresh()), 201, [
            'Location' => url('api/v1/workers/'.$worker->id),
        ]);
    }

    /**
     * Activar o desactivar (solo el Administrador). Desactivar es un borrado
     * lógico y cierra todas sus sesiones.
     */
    public function update(Request $request, $id)
    {
        $worker = Worker::withTrashed()->findOrFail($id);
        $this->authorize('update', $worker);
        $data = $this->validateResource($request, $this->type, $this->rules($request, $worker));
        $active = filter_var($data['attributes']['active'], FILTER_VALIDATE_BOOLEAN);

        DB::transaction(function () use ($worker, $active) {
            if ($active && $worker->trashed()) {
                $worker->restore();
            } elseif (! $active && ! $worker->trashed()) {
                $worker->delete();
                app(TokenService::class)->revokeAll($worker->id);
            }
        });

        return JsonApiResponse::make((new Document($request))->resource(Worker::withTrashed()->find($worker->id)));
    }

    protected function newQuery(Request $request): Builder
    {
        $query = Worker::query();
        $active = $request->input('filter.active');

        // Los inactivos solo los ve el Administrador.
        if ($request->user() && $request->user()->isAdmin()) {
            if ($active === 'false') {
                $query->onlyTrashed();
            } elseif ($active === 'all') {
                $query->withTrashed();
            }
        }

        return $query;
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        foreach (['itinerary' => 'itinerary_id', 'stop' => 'stop_id', 'rank' => 'rank_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                $query->where('first_name', 'like', '%'.$search.'%')->orWhere('last_name', 'like', '%'.$search.'%');
            });
        }
    }
}
