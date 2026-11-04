<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use App\Models\User;
use App\Models\Worker;
use App\Services\Accounts;
use App\Services\Memberships;
use App\Services\Permissions;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Pertenencias persona–Entidad (docs/11 §11.6).
 *
 * - Cada uno ve las suyas y, con workers.view, las de su ámbito.
 * - POST: el Administrador (workers.register) registra a una persona en una
 *   Entidad (si el carné ya existe, solo le añade la Entidad); con
 *   relationships.user, quien tenga entities.assign_members añade a una
 *   persona ya registrada.
 * - PATCH: active (workers.deactivate); itinerario y parada
 *   (members.assign); nombres, carné y teléfono de la persona (workers.edit).
 * - DELETE: darse de baja de la Entidad (o quitar a alguien, con
 *   entities.assign_members).
 */
class WorkerController extends ResourceController
{
    protected $model = Worker::class;

    protected $type = 'workers';

    protected $sortable = [
        'id' => 'workers.id',
        'firstName' => 'users.first_name',
        'firstSurname' => 'users.first_surname',
        'createdAt' => 'workers.created_at',
    ];

    protected $filterable = ['entity', 'itinerary', 'stop', 'active', 'search', 'user'];

    protected $includable = ['user', 'entity', 'itinerary', 'stop'];

    protected $defaultSort = 'firstSurname,firstName';

    /** @var Permissions */
    private $permissions;

    public function __construct(Permissions $permissions)
    {
        $this->permissions = $permissions;
    }

    protected function rules(Request $request, ?Model $model): array
    {
        return [];
    }

    public function store(Request $request)
    {
        $user = $request->user();

        if ($request->input('data.relationships.user.data.id') !== null) {
            return $this->addExistingPerson($request);
        }

        $data = $this->validateResource($request, 'workers', UserController::nameRules() + [
            'attributes.identityCard' => ['required', 'string', 'max:20'],
            'attributes.hasPhone' => ['sometimes', 'boolean'],
            'attributes.username' => ['sometimes', 'nullable', 'string', 'max:60'],
            'attributes.password' => ['sometimes', 'nullable', 'string'],
            'relationships.entity.data.type' => ['required', 'in:entities'],
            'relationships.entity.data.id' => ['required', 'exists:entities,id,deleted_at,NULL'],
            'relationships.itinerary.data.type' => ['sometimes', 'in:itineraries'],
            'relationships.itinerary.data.id' => ['sometimes', 'exists:itineraries,id,deleted_at,NULL'],
            'relationships.stop.data.type' => ['sometimes', 'in:stops'],
            'relationships.stop.data.id' => ['sometimes', 'exists:stops,id,deleted_at,NULL'],
        ]);
        $attributes = $data['attributes'];
        $relationships = $data['relationships'];
        $entity = Entity::findOrFail($relationships['entity']['data']['id']);
        $this->permissions->authorize($user, 'workers.register', $entity->id, null, 'No puede registrar trabajadores en esa Entidad.');
        list($itineraryId, $stopId) = $this->itineraryAndStop($relationships);

        if ($itineraryId !== null) {
            $this->permissions->authorize($user, 'members.assign', $entity->id, $itineraryId, 'No puede asignar ese itinerario.');
        }

        $result = DB::transaction(function () use ($user, $entity, $attributes, $itineraryId, $stopId) {
            $result = app(Accounts::class)->registerByAdmin(
                $user,
                $entity,
                UserController::names($attributes),
                $attributes['identityCard'],
                array_key_exists('hasPhone', $attributes) ? (bool) $attributes['hasPhone'] : true,
                isset($attributes['username']) ? $attributes['username'] : null,
                isset($attributes['password']) ? $attributes['password'] : null
            );

            if ($itineraryId !== null) {
                $result['worker'] = app(Memberships::class)->assignItinerary($result['worker'], $itineraryId, $stopId);
            }

            return $result;
        });

        $document = (new Document($request))->resource($result['worker']->fresh(), ['user', 'entity']);
        // Usuario y contraseña generados: solo en esta respuesta (docs/11 §11.5).
        $document['data']['meta'] = array_merge(isset($document['data']['meta']) ? $document['data']['meta'] : [], [
            'accountCreated' => $result['created'],
            'username' => $result['username'],
            'password' => $result['password'],
        ]);

        return JsonApiResponse::make($document, 201, ['Location' => url('api/v1/workers/'.$result['worker']->id)]);
    }

    public function update(Request $request, $id)
    {
        $worker = $this->findOrFail($request, $id);
        $user = $request->user();
        $data = $this->validateResource($request, 'workers', UserController::nameRules('attributes.', false) + [
            'attributes.active' => ['sometimes', 'boolean'],
            'attributes.identityCard' => ['sometimes', 'required', 'string', 'max:20'],
            'attributes.hasPhone' => ['sometimes', 'boolean'],
            'relationships.itinerary.data.type' => ['sometimes', 'in:itineraries'],
            'relationships.itinerary.data.id' => ['sometimes', 'exists:itineraries,id,deleted_at,NULL'],
            'relationships.stop.data.type' => ['sometimes', 'in:stops'],
            'relationships.stop.data.id' => ['sometimes', 'exists:stops,id,deleted_at,NULL'],
        ]);

        if (isset($data['id']) && (string) $data['id'] !== (string) $worker->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        $attributes = isset($data['attributes']) ? $data['attributes'] : [];
        $relationships = isset($data['relationships']) ? $data['relationships'] : [];
        $entityId = (int) $worker->entity_id;
        $currentItinerary = $worker->itinerary_id ? (int) $worker->itinerary_id : null;
        $person = UserController::names($attributes);
        $editsPerson = $person || array_key_exists('identityCard', $attributes) || array_key_exists('hasPhone', $attributes);

        if (array_key_exists('active', $attributes)) {
            $this->permissions->authorize($user, 'workers.deactivate', $entityId);
        }

        if ($editsPerson && (int) $worker->user_id !== (int) $user->id) {
            $this->permissions->authorize($user, 'workers.edit', $entityId, $currentItinerary);
        }

        list($itineraryId, $stopId) = $this->itineraryAndStop($relationships);

        if ($itineraryId !== null) {
            $this->permissions->authorize($user, 'members.assign', $entityId, $itineraryId, 'No puede asignar ese itinerario.');
        }

        if (! array_key_exists('active', $attributes) && ! $editsPerson && $itineraryId === null && (int) $worker->user_id !== (int) $user->id) {
            $this->permissions->authorize($user, 'workers.view', $entityId, $currentItinerary);
        }

        DB::transaction(function () use ($worker, $user, $attributes, $person, $itineraryId, $stopId) {
            $memberships = app(Memberships::class);
            $owner = User::withTrashed()->find($worker->user_id);

            if (array_key_exists('identityCard', $attributes)) {
                app(Accounts::class)->changeIdentityCard($owner, $attributes['identityCard']);
            }

            if ($person || array_key_exists('hasPhone', $attributes)) {
                $owner->fill($person);

                if (array_key_exists('hasPhone', $attributes)) {
                    $owner->has_phone = (bool) $attributes['hasPhone'];
                }

                $owner->save();
            }

            if ($itineraryId !== null) {
                $memberships->assignItinerary($worker, $itineraryId, $stopId, $user);
            }

            if (array_key_exists('active', $attributes)) {
                $memberships->setActive($worker, (bool) $attributes['active']);
            }
        });

        return JsonApiResponse::make((new Document($request))->resource(Worker::withTrashed()->find($worker->id), QueryParameters::readIncludes($request, $this->includable)));
    }

    /**
     * Darse de baja de la Entidad, o quitar a alguien (entities.assign_members).
     */
    public function destroy(Request $request, $id)
    {
        $worker = $this->findOrFail($request, $id);
        $user = $request->user();

        if ((int) $worker->user_id !== (int) $user->id) {
            $this->permissions->authorize($user, 'entities.assign_members', (int) $worker->entity_id);
        }

        if ($worker->trashed()) {
            throw JsonApiException::conflict('NOT_A_MEMBER', 'Esa pertenencia ya no está activa.');
        }

        app(Memberships::class)->leave($worker, $user);

        return response('', 204);
    }

    /**
     * Darse de baja del itinerario (y la parada), o quitárselo a alguien
     * (members.assign sobre su itinerario).
     */
    public function removeItinerary(Request $request, $id)
    {
        $worker = $this->findOrFail($request, $id);
        $user = $request->user();

        if ((int) $worker->user_id !== (int) $user->id) {
            $this->permissions->authorize($user, 'members.assign', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null);
        }

        app(Memberships::class)->removeItinerary($worker, $user);

        return response('', 204);
    }

    protected function newQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Worker::query()->select('workers.*')->join('users', 'users.id', '=', 'workers.user_id')->whereNull('users.deleted_at');
        $active = $request->input('filter.active');

        if ($active === 'false') {
            $query->onlyTrashed();
        } elseif ($active === 'all' || in_array($request->getMethod(), ['PATCH', 'DELETE'], true)) {
            $query->withTrashed();
        }

        $this->permissions->restrict($query, $user, 'workers.view', 'workers.entity_id', 'workers.itinerary_id', function ($query) use ($user) {
            $query->orWhere('workers.user_id', $user->id);
        });

        return $query;
    }

    /**
     * Para modificar o dar de baja no hace falta poder consultarla: lo
     * decide el permiso de cada acción.
     */
    protected function findOrFail(Request $request, $id): Model
    {
        if (in_array($request->getMethod(), ['PATCH', 'DELETE'], true)) {
            return Worker::withTrashed()->whereHas('user')->findOrFail($id);
        }

        return parent::findOrFail($request, $id);
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        foreach (['entity' => 'workers.entity_id', 'itinerary' => 'workers.itinerary_id', 'stop' => 'workers.stop_id', 'user' => 'workers.user_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                foreach (['first_name', 'middle_name', 'first_surname', 'second_surname', 'username'] as $column) {
                    $query->orWhere('users.'.$column, 'like', '%'.$search.'%');
                }

                // Por carné: solo coincidencia exacta (se guarda cifrado).
                if (\App\Support\IdentityCard::isValid($search)) {
                    $query->orWhere('users.identity_card_hash', \App\Support\IdentityCard::hash($search));
                }
            });
        }
    }

    /**
     * Añade a una persona ya registrada a la Entidad (entities.assign_members).
     */
    private function addExistingPerson(Request $request)
    {
        $data = $this->validateResource($request, 'workers', [
            'relationships.user.data.type' => ['required', 'in:users'],
            'relationships.user.data.id' => ['required', 'exists:users,id,deleted_at,NULL'],
            'relationships.entity.data.type' => ['required', 'in:entities'],
            'relationships.entity.data.id' => ['required', 'exists:entities,id,deleted_at,NULL'],
        ]);
        $entity = Entity::findOrFail($data['relationships']['entity']['data']['id']);
        $this->permissions->authorize($request->user(), 'entities.assign_members', $entity->id);
        $person = User::findOrFail($data['relationships']['user']['data']['id']);
        $worker = app(Memberships::class)->join($person, $entity, $request->user());
        app(\App\Services\Notices::class)->send([(int) $person->id], \App\Models\Notice::TYPE_ENTITY_ADDED, null, null, (int) $request->user()->id,
            ['entity' => $entity->abbreviation, 'by' => $request->user()->fullName()]);

        return JsonApiResponse::make((new Document($request))->resource($worker->fresh(), ['user', 'entity']), 201, [
            'Location' => url('api/v1/workers/'.$worker->id),
        ]);
    }

    /**
     * Itinerario y parada van siempre juntos.
     *
     * @return array [itineraryId|null, stopId|null]
     */
    private function itineraryAndStop(array $relationships): array
    {
        $itineraryId = isset($relationships['itinerary']['data']['id']) ? (int) $relationships['itinerary']['data']['id'] : null;
        $stopId = isset($relationships['stop']['data']['id']) ? (int) $relationships['stop']['data']['id'] : null;

        if ($itineraryId === null && $stopId !== null) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el itinerario', 'Indique el itinerario de la parada.', ['pointer' => '/data/relationships/itinerary/data/id']);
        }

        if ($itineraryId !== null && $stopId === null) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta la parada', 'Indique la parada en el itinerario.', ['pointer' => '/data/relationships/stop/data/id']);
        }

        return [$itineraryId, $stopId];
    }
}
