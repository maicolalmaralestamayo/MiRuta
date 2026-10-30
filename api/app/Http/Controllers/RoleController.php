<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\Worker;
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

    protected $includable = ['worker'];

    protected function rules(Request $request, ?Model $model): array
    {
        return [];
    }

    /**
     * Tipo de baja que se registra al quitar el rol.
     */
    abstract protected function leaveType(): string;

    /**
     * Quién, además del propio trabajador, puede quitar el rol (el Administrador siempre).
     */
    abstract protected function canRemoveOthers(Worker $user): bool;

    /**
     * Darse de baja (el propio trabajador) o quitar el rol a otro (un superior).
     * Queda registrado como solicitud de baja aprobada.
     */
    public function destroy(Request $request, $id)
    {
        $role = $this->model::findOrFail($id);
        $user = $request->user();
        $isSelf = (int) $role->worker_id === (int) $user->id;

        if (! $isSelf && ! $user->isAdmin() && ! $this->canRemoveOthers($user)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes quitar este rol.');
        }

        app(Applications::class)->leave(Worker::findOrFail($role->worker_id), $this->leaveType(), $role->itinerary_id, $user);

        return response('', 204);
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($worker = $parameters->filter('worker')) {
            $query->where('worker_id', $worker);
        }
    }
}
