<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Worker;
use App\Support\Tenancy;
use App\Services\Applications;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Roles vigentes. Se crean al aprobar solicitudes; aquí solo se consultan
 * (y se dan de baja, en los controladores concretos).
 */
abstract class RoleController extends ResourceController
{
    protected $filterable = ['worker'];

    protected $includable = ['worker', 'worker.user'];

    protected function rules(Request $request, ?Model $model): array
    {
        return [];
    }

    /**
     * Tipo de baja que se registra al quitar el rol.
     */
    abstract protected function leaveType(): string;

    /**
     * Darse de baja (el propio trabajador) o quitar el rol a otro (un superior).
     * Queda registrado como solicitud de baja aprobada.
     */
    public function destroy(Request $request, $id)
    {
        $role = $this->findOrFail($request, $id);
        $user = $request->user();
        $worker = Worker::findOrFail($role->worker_id);
        $applications = app(Applications::class);
        $itineraryId = $role->itinerary_id ? (int) $role->itinerary_id : null;
        $isSelf = (int) $role->worker_id === $user->workerId();

        if (! $isSelf && ! $applications->canRemove($user, $worker, $this->leaveType(), $itineraryId)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes quitar este rol.');
        }

        $applications->leave($worker, $this->leaveType(), $itineraryId, $user);

        return response('', 204);
    }

    /**
     * Solo los de su Entidad (todos, para el Administrador).
     */
    protected function newQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = $this->model::query();

        return $user->isAdmin() ? $query : $query->whereHas('worker', function (Builder $query) use ($user) {
            $query->where('entity_id', $user->entityId());
        });
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }
    }
}
