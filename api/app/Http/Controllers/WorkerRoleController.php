<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Role;
use App\Models\Worker;
use App\Models\WorkerRole;
use App\Services\Applications;
use App\Services\Memberships;
use App\Services\Permissions;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Roles de las personas en cada Entidad (docs/11 §11.16).
 *
 * - Asignar o quitar directamente: roles.assign en la Entidad, y solo los
 *   roles de los que alguno de sus roles es aprobador (el Administrador, todos).
 * - Darse de baja de un rol: la propia persona (DELETE).
 */
class WorkerRoleController extends Controller
{
    const SORTABLE = ['id' => 'id', 'createdAt' => 'created_at'];

    const INCLUDABLE = ['worker', 'worker.user', 'role', 'itinerary'];

    /** @var Permissions */
    private $permissions;

    public function __construct(Permissions $permissions)
    {
        $this->permissions = $permissions;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['worker', 'entity', 'role', 'itinerary', 'user'], self::INCLUDABLE, 'id');
        $query = $this->visible($request);

        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }

        foreach (['role' => 'role_id', 'itinerary' => 'itinerary_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->where($column, $value);
            }
        }

        foreach (['entity' => 'entity_id', 'user' => 'user_id'] as $filter => $column) {
            if ($value = $parameters->filter($filter)) {
                $query->whereHas('worker', function (Builder $query) use ($column, $value) {
                    $query->where($column, $value);
                });
            }
        }

        $paginator = $parameters->applySort($query, self::SORTABLE)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->visible($request)->findOrFail($id), QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    /**
     * relationships: worker, role e itinerary (si el rol es por itinerario).
     */
    public function store(Request $request, Memberships $memberships)
    {
        $data = $this->validateResource($request, 'worker-roles', [
            'relationships.worker.data.type' => ['required', 'in:workers'],
            'relationships.worker.data.id' => ['required', 'integer'],
            'relationships.role.data.type' => ['required', 'in:roles'],
            'relationships.role.data.id' => ['required', 'exists:roles,id,deleted_at,NULL'],
            'relationships.itinerary.data.type' => ['sometimes', 'in:itineraries'],
            'relationships.itinerary.data.id' => ['sometimes', 'exists:itineraries,id,deleted_at,NULL'],
        ]);
        $worker = Worker::whereHas('user')->find($data['relationships']['worker']['data']['id']);

        if (! $worker) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Pertenencia no válida', 'La pertenencia no existe o no está activa.', ['pointer' => '/data/relationships/worker']);
        }

        $role = Role::findOrFail($data['relationships']['role']['data']['id']);
        $this->authorizeAssign($request, $role, (int) $worker->entity_id);
        $itineraryId = isset($data['relationships']['itinerary']['data']['id']) ? (int) $data['relationships']['itinerary']['data']['id'] : null;
        $workerRole = $memberships->assignRole($worker, $role, $itineraryId, $request->user());

        return JsonApiResponse::make((new Document($request))->resource($workerRole->fresh()), 201, ['Location' => url('api/v1/worker-roles/'.$workerRole->id)]);
    }

    /**
     * Darse de baja del rol (la propia persona) o quitárselo a otro.
     */
    public function destroy(Request $request, Memberships $memberships, $id)
    {
        $workerRole = WorkerRole::findOrFail($id);
        $worker = Worker::withTrashed()->findOrFail($workerRole->worker_id);

        if ((int) $worker->user_id !== (int) $request->user()->id) {
            $this->authorizeAssign($request, Role::withTrashed()->findOrFail($workerRole->role_id), (int) $worker->entity_id);
        }

        $memberships->removeRole($workerRole, $request->user());

        return response('', 204);
    }

    private function authorizeAssign(Request $request, Role $role, int $entityId): void
    {
        if (! app(Applications::class)->canApproveRole($request->user(), (int) $role->id, $entityId, 'roles.assign')) {
            throw Permissions::forbidden('No puede asignar ni quitar ese rol en esa Entidad.');
        }
    }

    /**
     * Los suyos y los de las Entidades o itinerarios de su ámbito de
     * roles.assign o workers.view.
     */
    private function visible(Request $request): Builder
    {
        $user = $request->user();
        $query = WorkerRole::query();
        $assign = $this->permissions->scope($user, 'roles.assign');
        $view = $this->permissions->scope($user, 'workers.view');

        if ($assign['all'] || $view['all']) {
            return $query;
        }

        $entities = array_values(array_unique(array_merge($assign['entities'], $view['entities'])));
        $itineraries = $view['itineraries'];

        return $query->whereHas('worker', function (Builder $query) use ($user, $entities, $itineraries) {
            $query->where(function (Builder $query) use ($user, $entities, $itineraries) {
                $query->where('user_id', $user->id)
                    ->orWhereIn('entity_id', $entities ?: [0])
                    ->orWhereIn('itinerary_id', $itineraries ?: [0]);
            });
        });
    }
}
