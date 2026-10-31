<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Application;
use App\Models\Entity;
use App\Models\User;
use App\Models\Worker;
use App\Services\Accounts;
use App\Services\Applications;
use App\Services\TokenService;
use App\Support\Tenancy;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Trabajadores de una Entidad.
 *
 * - Cada uno ve los de su Entidad; el Administrador, todos.
 * - Un superior (Jefe de Transporte, Jefe de itinerario o el Administrador)
 *   puede registrar a un trabajador sin teléfono: se le da un código de
 *   activación (docs/08-version-2.md §8.3).
 * - Activar y desactivar: solo el Administrador.
 */
class WorkerController extends ResourceController
{
    protected $model = Worker::class;

    protected $type = 'workers';

    protected $sortable = [
        'id' => 'workers.id',
        'pass' => 'workers.pass',
        'firstName' => 'users.first_name',
        'firstSurname' => 'users.first_surname',
        'createdAt' => 'workers.created_at',
    ];

    protected $filterable = ['entity', 'itinerary', 'stop', 'rank', 'active', 'search', 'pass', 'activated'];

    protected $includable = ['user', 'entity', 'rank', 'itinerary', 'stop'];

    protected $defaultSort = 'firstSurname,firstName';

    protected function rules(Request $request, ?Model $model): array
    {
        return ['attributes.active' => ['required', 'boolean']];
    }

    /**
     * Un superior registra a un trabajador sin teléfono. Devuelve el código
     * de activación (solo esta vez) en meta.activationCode.
     */
    public function store(Request $request)
    {
        $user = $request->user();

        if (! $user->isAdmin() && ! $user->isTransportChief() && ! $user->isItineraryChief()) {
            throw new AuthorizationException();
        }

        $data = $this->validateResource($request, 'workers', UserController::nameRules() + [
            'attributes.pass' => ['required', 'integer', 'min:1', 'max:4294967295'],
            'attributes.sex' => ['required', 'in:F,M'],
            'relationships.rank.data.type' => ['required', 'in:ranks'],
            'relationships.rank.data.id' => ['required', 'exists:ranks,id,deleted_at,NULL'],
            'relationships.entity.data.type' => [$user->isAdmin() ? 'required' : 'sometimes', 'in:entities'],
            'relationships.entity.data.id' => [$user->isAdmin() ? 'required' : 'sometimes', 'exists:entities,id,deleted_at,NULL'],
            'relationships.itinerary.data.type' => ['sometimes', 'in:itineraries'],
            'relationships.itinerary.data.id' => ['sometimes', 'exists:itineraries,id,deleted_at,NULL'],
            'relationships.stop.data.type' => ['sometimes', 'in:stops'],
            'relationships.stop.data.id' => ['sometimes', 'exists:stops,id,deleted_at,NULL'],
        ]);
        $attributes = $data['attributes'];
        $relationships = isset($data['relationships']) ? $data['relationships'] : [];
        $entity = $user->isAdmin() ? Entity::findOrFail($relationships['entity']['data']['id']) : Entity::findOrFail($user->entityId());
        $itineraryId = isset($relationships['itinerary']['data']['id']) ? (int) $relationships['itinerary']['data']['id'] : null;

        // El Jefe de itinerario registra a los de su itinerario.
        if (! $user->managesEntity($entity->id)) {
            $itineraryId = $itineraryId ?: ($user->chiefItineraryIds()[0] ?? null);

            if (! $user->isChiefOf($itineraryId)) {
                throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo puedes registrar trabajadores de tu itinerario.');
            }
        }

        Tenancy::ensureSame($entity->id, 'itineraries', $itineraryId, '/data/relationships/itinerary');

        if ($itineraryId === null && isset($relationships['stop']['data']['id'])) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el itinerario', 'Indica el itinerario de la parada.', ['pointer' => '/data/relationships/itinerary/data/id']);
        }

        if ($itineraryId !== null && ! isset($relationships['stop']['data']['id'])) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta la parada', 'Indica la parada del trabajador en el itinerario.', ['pointer' => '/data/relationships/stop/data/id']);
        }

        list($worker, $code) = DB::transaction(function () use ($user, $entity, $attributes, $relationships, $itineraryId) {
            list($worker, $code) = app(Accounts::class)->registerBySuperior(
                $user, $entity, UserController::names($attributes), (int) $attributes['pass'], $attributes['sex'],
                (int) $relationships['rank']['data']['id']
            );

            if ($itineraryId !== null) {
                $stopId = isset($relationships['stop']['data']['id']) ? (int) $relationships['stop']['data']['id'] : null;
                app(Applications::class)->create($user, $worker, [
                    'attributes' => ['type' => Application::TYPE_ITINERARY_MEMBERSHIP],
                    'relationships' => [
                        'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itineraryId]],
                        'stop' => ['data' => ['type' => 'stops', 'id' => (string) $stopId]],
                    ],
                ]);
            }

            return [$worker, $code];
        });

        return $this->withActivationCode($request, $worker->fresh(), $code, 201);
    }

    /**
     * Código de activación nuevo (si se perdió o caducó). Los mismos
     * superiores que pueden registrar a ese trabajador.
     */
    public function activationCode(Request $request, $id)
    {
        $worker = $this->findOrFail($request, $id);
        $user = $request->user();

        if (! $user->managesEntity($worker->entity_id) && ! $user->isChiefOf($worker->itinerary_id ? (int) $worker->itinerary_id : null)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes generar el código de este trabajador.');
        }

        $code = app(Accounts::class)->issueActivationCode($worker->user, $user);

        return $this->withActivationCode($request, $worker, $code, 201);
    }

    /**
     * Activar o desactivar (solo el Administrador). Desactivar la cuenta y
     * el trabajador es un borrado lógico y cierra todas sus sesiones.
     */
    public function update(Request $request, $id)
    {
        if (! $request->user()->isAdmin()) {
            throw new AuthorizationException();
        }

        $worker = Worker::withTrashed()->findOrFail($id);
        $data = $this->validateResource($request, $this->type, $this->rules($request, $worker));
        $active = filter_var($data['attributes']['active'], FILTER_VALIDATE_BOOLEAN);

        DB::transaction(function () use ($worker, $active) {
            $user = User::withTrashed()->find($worker->user_id);

            if ($active) {
                $worker->restore();
                $user->restore();
            } else {
                $worker->delete();
                $user->delete();
                app(TokenService::class)->revokeAll($user->id);
            }
        });

        return JsonApiResponse::make((new Document($request))->resource(Worker::withTrashed()->find($worker->id)));
    }

    protected function newQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Worker::query()->select('workers.*')->join('users', 'users.id', '=', 'workers.user_id');
        $active = $request->input('filter.active');

        // Los inactivos solo los ve el Administrador.
        if ($user->isAdmin()) {
            if ($active === 'false') {
                $query->onlyTrashed();
            } elseif ($active === 'all') {
                $query->withTrashed();
            }

            return $query;
        }

        return $query->visibleTo($user);
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        foreach (['entity' => 'workers.entity_id', 'itinerary' => 'workers.itinerary_id', 'stop' => 'workers.stop_id', 'rank' => 'workers.rank_id', 'pass' => 'workers.pass'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        if ($parameters->filter('activated') !== null) {
            $parameters->filter('activated') === 'true'
                ? $query->whereNotNull('users.username')
                : $query->whereNull('users.username');
        }

        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                foreach (['first_name', 'middle_name', 'first_surname', 'second_surname', 'username'] as $column) {
                    $query->orWhere('users.'.$column, 'like', '%'.$search.'%');
                }

                if (ctype_digit($search)) {
                    $query->orWhere('workers.pass', (int) $search);
                }
            });
        }
    }

    private function withActivationCode(Request $request, Worker $worker, string $code, int $status)
    {
        $document = (new Document($request))->resource($worker, ['user']);
        $expiresAt = app(Accounts::class)->activationExpiresAt($worker->user);
        $document['data']['meta'] = array_merge(isset($document['data']['meta']) ? $document['data']['meta'] : [], [
            'activationCode' => substr($code, 0, 4).'-'.substr($code, 4),
            'activationExpiresAt' => $expiresAt ? $expiresAt->toIso8601String() : null,
        ]);

        return JsonApiResponse::make($document, $status);
    }
}
