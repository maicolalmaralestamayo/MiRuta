<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use App\Models\User;
use App\Models\Worker;
use App\Services\Access;
use App\Services\Accounts;
use App\Services\Memberships;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * La persona en una Entidad (recurso "workers"): sección Personas de Gestión
 * (con include=user) y sus movimientos (docs/11 §11.26 y §11.30).
 *
 * - Administrador: todo (registrar, cambiar de Entidad, itinerario y parada,
 *   asignar y quitar el rol de Jefe, activar, sacar de la Entidad).
 * - Jefe de itinerario: en su itinerario, cambia la parada de sus personas,
 *   las saca de él o pone en él a personas de su Entidad, y las activa o
 *   desactiva.
 * - Trabajador: se cambia de parada en su itinerario, sale del itinerario y
 *   sale de la Entidad.
 */
class WorkerController extends Controller
{
    public const INCLUDABLE = ['user', 'entity', 'itinerary', 'stop'];

    public function __construct(private Access $access, private Memberships $memberships)
    {
    }

    public function index(Request $request)
    {
        $sortable = [
            'id' => 'id',
            'createdAt' => 'created_at',
            'name' => User::select('first_name')->whereColumn('users.id', 'workers.user_id'),
            'surname' => User::select('first_surname')->whereColumn('users.id', 'workers.user_id'),
        ];
        $parameters = QueryParameters::fromRequest($request, $sortable,
            ['entity', 'itinerary', 'stop', 'user', 'search', 'active', 'chief'], self::INCLUDABLE, 'name,surname');
        $query = $this->visible($request->user());

        foreach (['entity' => 'entity_id', 'itinerary' => 'itinerary_id', 'stop' => 'stop_id', 'user' => 'user_id'] as $filter => $column) {
            $value = $parameters->filter($filter);

            if ($value === 'none' && in_array($filter, ['itinerary', 'stop'], true)) {
                $query->whereNull($column);
            } elseif ($value !== null) {
                $query->where($column, (int) $value);
            }
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
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
        $worker = $this->visible($request->user())->findOrFail($id);

        return $this->respond($request, $worker, QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    /**
     * Solo el Administrador:
     * - persona existente (relationships.user) en una Entidad (también él mismo);
     * - persona nueva: nombres, carné y, si quiere, usuario y contraseña (si
     *   no, se proponen; se devuelven en meta para comunicárselos). Si el carné
     *   ya existe, no se crea otra cuenta: se le añade la Entidad.
     * Con relationships.itinerary y relationships.stop se le pone además en ellos.
     */
    public function store(Request $request, Accounts $accounts)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador registra personas y las añade a una Entidad.');
        $data = $this->validateResource($request, 'workers', $this->relationshipRules('entity', 'entities', 'entities', true)
            + $this->relationshipRules('user', 'users', 'users', false)
            + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', false)
            + $this->relationshipRules('stop', 'stops', 'stops', false)
            + UserController::nameRules('attributes.', false) + [
                'attributes.identityCard' => ['sometimes', 'string', 'max:20'],
                'attributes.username' => ['sometimes', 'nullable', 'string', 'max:60'],
                'attributes.password' => ['sometimes', 'nullable', 'string'],
            ]);
        $entity = Entity::findOrFail($this->relationshipId($data, 'entity'));
        $userId = $this->relationshipId($data, 'user');
        $attributes = $data['attributes'] ?? [];
        $meta = [];

        $worker = DB::transaction(function () use ($data, $entity, $userId, $attributes, $accounts, &$meta) {
            if ($userId !== null) {
                $user = User::findOrFail($userId);

                if (Worker::where('user_id', $user->id)->where('entity_id', $entity->id)->exists()) {
                    throw JsonApiException::conflict('ALREADY_MEMBER', 'Esa persona ya pertenece a la Entidad.', '/data/relationships/user');
                }

                $worker = $this->memberships->join($user, $entity);
            } else {
                foreach (['firstName', 'firstSurname', 'secondSurname', 'identityCard'] as $field) {
                    if (empty($attributes[$field])) {
                        throw new JsonApiException(422, 'VALIDATION_ERROR', 'Faltan datos',
                            'Para registrar a una persona hacen falta sus nombres, sus apellidos y su carné (o relationships.user si ya tiene cuenta).',
                            ['pointer' => '/data/attributes/'.$field]);
                    }
                }

                $result = $accounts->registerByAdmin($entity, UserController::names($attributes), $attributes['identityCard'],
                    $attributes['username'] ?? null, $attributes['password'] ?? null);
                $worker = $result['worker'];
                $meta = ['created' => $result['created'], 'username' => $result['username'], 'password' => $result['password']];
            }

            if ($this->relationshipId($data, 'itinerary') !== null) {
                $this->memberships->place($worker, $this->relationshipId($data, 'itinerary'), $this->relationshipId($data, 'stop'));
            }

            return $worker;
        });

        $document = (new Document($request))->resource($worker->fresh(), ['user']);

        if ($meta) {
            $document['meta'] = $meta;
        }

        return JsonApiResponse::make($document, 201, ['Location' => url('api/v1/workers/'.$worker->id)]);
    }

    /**
     * attributes.active, attributes.isChief, relationships.itinerary y
     * relationships.stop (null = quitar). Cambiar de Entidad: relationships.entity
     * (solo el Administrador; se le quitan itinerario, parada y jefatura en la anterior).
     */
    public function update(Request $request, $id)
    {
        $actor = $request->user();
        $worker = $this->visible($actor)->findOrFail($id);
        $data = $this->validateResource($request, 'workers', [
            'attributes.active' => ['sometimes', 'boolean'],
            'attributes.isChief' => ['sometimes', 'boolean'],
        ] + $this->relationshipRules('itinerary', 'itineraries', 'itineraries', false, true)
          + $this->relationshipRules('stop', 'stops', 'stops', false, true)
          + $this->relationshipRules('entity', 'entities', 'entities', false));

        if (isset($data['id']) && (string) $data['id'] !== (string) $worker->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        $attributes = $data['attributes'] ?? [];

        $worker = DB::transaction(function () use ($actor, $worker, $data, $attributes) {
            if ($this->hasRelationship($data, 'entity') && (int) $this->relationshipId($data, 'entity') !== (int) $worker->entity_id) {
                $worker = $this->changeEntity($actor, $worker, $this->relationshipId($data, 'entity'));
            }

            if ($this->hasRelationship($data, 'itinerary') || $this->hasRelationship($data, 'stop')) {
                $itineraryId = $this->hasRelationship($data, 'itinerary') ? $this->relationshipId($data, 'itinerary') : ($worker->itinerary_id ? (int) $worker->itinerary_id : null);
                $stopId = $this->hasRelationship($data, 'stop') ? $this->relationshipId($data, 'stop')
                    : ((int) $itineraryId === (int) $worker->itinerary_id && $worker->stop_id ? (int) $worker->stop_id : null);
                $this->authorizePlacement($actor, $worker, $itineraryId);
                $this->memberships->place($worker, $itineraryId, $stopId);
            }

            if (array_key_exists('active', $attributes)) {
                if (! $this->access->isAdmin($actor) && ! ($worker->itinerary_id && $this->access->isChiefOf($actor, $worker->itinerary_id))) {
                    throw Access::forbidden('Solo el Administrador, o el Jefe de su itinerario, activan o desactivan a una persona.');
                }
                $worker->active = (bool) $attributes['active'];
                $worker->save();
            }

            if (array_key_exists('isChief', $attributes)) {
                $this->access->requireAdmin($actor, 'Solo el Administrador asigna y quita el rol de Jefe de itinerario.');

                if ($attributes['isChief']) {
                    if (! $worker->itinerary_id) {
                        throw new JsonApiException(422, 'ITINERARY_REQUIRED', 'Falta el itinerario',
                            'Para ser Jefe de itinerario hay que estar en un itinerario (relationships.itinerary).', ['pointer' => '/data/relationships/itinerary']);
                    }
                    $this->memberships->makeChief($worker, (int) $worker->itinerary_id);
                } else {
                    $this->memberships->removeChief($worker);
                }
            }

            return $worker;
        });

        return $this->respond($request, $worker->fresh(), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    /**
     * Sacar de la Entidad: el Administrador a cualquiera; cada uno a sí mismo («Salir de la Entidad»).
     */
    public function destroy(Request $request, $id)
    {
        $actor = $request->user();
        $worker = $this->visible($actor)->findOrFail($id);

        if (! $this->access->isAdmin($actor) && (int) $worker->user_id !== (int) $actor->id) {
            throw Access::forbidden('Solo el Administrador saca a otra persona de una Entidad.');
        }

        $this->memberships->leave($worker);

        return $this->noContent();
    }

    private function changeEntity(User $actor, Worker $worker, int $entityId): Worker
    {
        $this->access->requireAdmin($actor, 'Solo el Administrador cambia a una persona de Entidad.');

        if (Worker::where('user_id', $worker->user_id)->where('entity_id', $entityId)->exists()) {
            throw JsonApiException::conflict('ALREADY_MEMBER', 'Esa persona ya pertenece a esa Entidad.', '/data/relationships/entity');
        }

        $worker->forceFill(['entity_id' => $entityId, 'itinerary_id' => null, 'stop_id' => null, 'is_chief' => false])->save();
        $this->access->flush((int) $worker->user_id);

        return $worker;
    }

    /**
     * Quién puede poner o quitar el itinerario y la parada.
     */
    private function authorizePlacement(User $actor, Worker $worker, ?int $itineraryId): void
    {
        if ($this->access->isAdmin($actor)) {
            return;
        }

        $same = (int) $itineraryId === (int) $worker->itinerary_id;

        // El propio trabajador: cambiarse de parada en su itinerario o salir del itinerario.
        if ((int) $worker->user_id === (int) $actor->id && ($same || $itineraryId === null)) {
            return;
        }

        // El Jefe: dentro de su itinerario, sacar de él o poner en él.
        $chiefOf = $this->access->chiefItineraryId($actor);

        if ($chiefOf !== null && (($same && $chiefOf === (int) $itineraryId)
            || ($itineraryId === null && $chiefOf === (int) $worker->itinerary_id)
            || ($chiefOf === (int) $itineraryId && $this->access->workerIn($actor, $worker->entity_id)))) {
            return;
        }

        throw Access::forbidden($itineraryId === null || $same
            ? 'No puede cambiar la parada ni el itinerario de esta persona.'
            : 'Para entrar en otro itinerario hay que solicitarlo (o que lo incluya su Jefe por QR).');
    }

    private function visible(User $viewer): Builder
    {
        $query = Worker::query();

        if ($this->access->isAdmin($viewer)) {
            return $query;
        }

        $query->whereIn('entity_id', $this->access->entityIds($viewer) ?: [0]);

        // Lo desactivado solo lo ven el Administrador y el Jefe (en su itinerario).
        $chiefOf = $this->access->chiefItineraryId($viewer);

        return $query->where(fn ($q) => $q->where('active', true)->orWhere('user_id', $viewer->id)
            ->when($chiefOf !== null, fn ($q) => $q->orWhere('itinerary_id', $chiefOf)));
    }
}
