<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\User;
use App\Models\Worker;
use App\Services\Applications;
use App\Services\Memberships;
use App\Services\Permissions;
use App\Services\TokenService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Personas (users). Cada uno ve la suya, las de las pertenencias de su
 * ámbito de workers.view y las de las solicitudes que puede resolver; con
 * workers.view «all», todas (también las que no tienen Entidad). Desactivar
 * y reactivar una cuenta (eliminar trabajadores): workers.delete.
 */
class AccountController extends ResourceController
{
    protected $model = User::class;

    protected $type = 'users';

    protected $sortable = ['id' => 'id', 'username' => 'username', 'firstSurname' => 'first_surname', 'createdAt' => 'created_at'];

    protected $filterable = ['search', 'active', 'hasWorker', 'entity'];

    protected $includable = [];

    protected $defaultSort = 'firstSurname';

    protected function rules(Request $request, ?Model $model): array
    {
        return ['attributes.active' => ['required', 'boolean']];
    }

    public function update(Request $request, $id)
    {
        app(Permissions::class)->authorize($request->user(), 'workers.delete');
        $user = User::withTrashed()->findOrFail($id);
        $data = $this->validateResource($request, $this->type, $this->rules($request, $user));
        $active = filter_var($data['attributes']['active'], FILTER_VALIDATE_BOOLEAN);

        if (! $active && $user->isAdmin() && User::where('is_admin', true)->where('id', '<>', $user->id)->doesntExist()) {
            throw \App\JsonApi\JsonApiException::conflict('LAST_ADMIN', 'Siempre tiene que haber al menos un Administrador.');
        }

        DB::transaction(function () use ($user, $active) {
            if ($active) {
                $user->restore();
            } else {
                $user->delete();
                app(TokenService::class)->revokeAll($user->id);

                foreach (Worker::where('user_id', $user->id)->get() as $worker) {
                    app(Memberships::class)->afterDriveLost($worker);
                }
            }
        });

        return JsonApiResponse::make((new Document($request))->resource(User::withTrashed()->find($user->id)));
    }

    protected function newQuery(Request $request): Builder
    {
        $viewer = $request->user();
        $query = User::query();
        $active = $request->input('filter.active');
        $permissions = app(Permissions::class);

        if ($active === 'false') {
            $query->onlyTrashed();
        } elseif ($active === 'all') {
            $query->withTrashed();
        }

        $scope = $permissions->scope($viewer, 'workers.view');

        if ($scope['all']) {
            return $query;
        }

        $workers = Worker::query()->select('user_id');
        $permissions->restrict($workers, $viewer, 'workers.view', 'entity_id', 'itinerary_id');
        $applicants = app(Applications::class)->visibleTo($viewer)->select('user_id');

        return $query->where(function (Builder $query) use ($viewer, $workers, $applicants) {
            $query->where('users.id', $viewer->id)
                ->orWhereIn('users.id', $workers->toBase())
                ->orWhereIn('users.id', $applicants->toBase());
        });
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                foreach (['username', 'first_name', 'middle_name', 'first_surname', 'second_surname'] as $column) {
                    $query->orWhere($column, 'like', '%'.$search.'%');
                }

                if (\App\Support\IdentityCard::isValid($search)) {
                    $query->orWhere('identity_card_hash', \App\Support\IdentityCard::hash($search));
                }
            });
        }

        if ($parameters->filter('hasWorker') !== null) {
            $parameters->filter('hasWorker') === 'true' ? $query->has('workers') : $query->doesntHave('workers');
        }

        if ($entity = $parameters->filter('entity')) {
            $query->whereHas('workers', function (Builder $query) use ($entity) {
                $query->where('entity_id', $entity);
            });
        }
    }
}
