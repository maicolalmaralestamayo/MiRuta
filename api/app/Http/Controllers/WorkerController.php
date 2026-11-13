<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Services\Access;
use App\Services\Accounts;
use App\Services\Memberships;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * La persona en una Entidad (recurso "workers"): listas de Gestión (con
 * include=user) y sus movimientos (docs/11 §11.26, §11.30 y §11.58). Sus
 * itinerarios en la Entidad, con parada y jefatura, son el recurso
 * "worker-itineraries" (WorkerItineraryController).
 *
 * - Administrador: registrar, añadir a una Entidad («Asociar Entidad»),
 *   activar y sacar de la Entidad.
 * - Jefe de itinerario: activa o desactiva a las personas de su itinerario.
 * - Trabajador: sale de la Entidad.
 *
 * filter[itinerary]=none: las pertenencias sin ningún itinerario en su Entidad
 * («Trabajadores sin itinerario»); filter[itinerary]=N y filter[stop]=N|none,
 * las que tienen ese itinerario / esa parada (o alguno sin parada).
 */
class WorkerController extends Controller
{
    public const INCLUDABLE = ['user', 'entity'];

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

        foreach (['entity' => 'entity_id', 'user' => 'user_id'] as $filter => $column) {
            if (($value = $parameters->filter($filter)) !== null) {
                $query->where($column, (int) $value);
            }
        }

        $itinerary = $parameters->filter('itinerary');

        if ($itinerary === 'none') {
            $query->whereNotIn('id', WorkerItinerary::select('worker_id'));
        } elseif ($itinerary !== null) {
            $query->whereIn('id', WorkerItinerary::where('itinerary_id', (int) $itinerary)->select('worker_id'));
        }

        $stop = $parameters->filter('stop');

        if ($stop === 'none') {
            $query->whereIn('id', WorkerItinerary::whereNull('stop_id')->select('worker_id'));
        } elseif ($stop !== null) {
            $query->whereIn('id', WorkerItinerary::where('stop_id', (int) $stop)->select('worker_id'));
        }

        if ($parameters->filter('active') !== null) {
            $query->where('active', $parameters->filter('active') === 'true');
        }

        if ($parameters->filter('chief') !== null) {
            $chiefs = WorkerItinerary::where('is_chief', true)->select('worker_id');
            $parameters->filter('chief') === 'true' ? $query->whereIn('id', $chiefs) : $query->whereNotIn('id', $chiefs);
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
     * Con relationships.itinerary (de esa Entidad) y relationships.stop se le
     * añade además ese itinerario. Sin usuario o contraseña, el sistema los
     * genera (se devuelven en meta).
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
                $itinerary = Itinerary::findOrFail($this->relationshipId($data, 'itinerary'));

                if ((int) $itinerary->entity_id !== (int) $entity->id) {
                    throw new JsonApiException(422, 'ITINERARY_NOT_IN_ENTITY', 'Itinerario de otra Entidad',
                        'El itinerario no es de esa Entidad.', ['pointer' => '/data/relationships/itinerary']);
                }

                $this->memberships->addItinerary(User::findOrFail($worker->user_id), $itinerary, $this->relationshipId($data, 'stop'));
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
     * attributes.active: el Administrador o el Jefe de uno de sus itinerarios en esa Entidad.
     */
    public function update(Request $request, $id)
    {
        $actor = $request->user();
        $worker = $this->visible($actor)->findOrFail($id);
        $data = $this->validateResource($request, 'workers', ['attributes.active' => ['sometimes', 'boolean']]);

        if (isset($data['id']) && (string) $data['id'] !== (string) $worker->id) {
            throw JsonApiException::conflict('ID_MISMATCH', 'El id del documento no coincide con el de la URL.', '/data/id');
        }

        if (array_key_exists('active', $data['attributes'] ?? [])) {
            $chiefOf = $this->access->chiefItineraryId($actor);

            if (! $this->access->isAdmin($actor)
                && ! ($chiefOf !== null && WorkerItinerary::where('worker_id', $worker->id)->where('itinerary_id', $chiefOf)->exists())) {
                throw Access::forbidden('Solo el Administrador, o el Jefe de su itinerario, activan o desactivan a una persona.');
            }

            $worker->active = (bool) $data['attributes']['active'];
            $worker->save();
            $this->access->flush((int) $worker->user_id);
        }

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
            ->when($chiefOf !== null, fn ($q) => $q->orWhereIn('id', WorkerItinerary::where('itinerary_id', $chiefOf)->select('worker_id'))));
    }
}
