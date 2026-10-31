<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\User;
use App\Models\Worker;
use App\Services\TokenService;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Cuentas (solo el Administrador): incluye las que aún no se unieron a
 * ninguna Entidad. Activar y desactivar.
 */
class AccountController extends ResourceController
{
    protected $model = User::class;

    protected $type = 'users';

    protected $sortable = ['id' => 'id', 'username' => 'username', 'firstSurname' => 'first_surname', 'createdAt' => 'created_at'];

    protected $filterable = ['search', 'active', 'hasWorker'];

    protected $includable = ['worker', 'worker.entity'];

    protected $defaultSort = 'firstSurname';

    protected function rules(Request $request, ?Model $model): array
    {
        return ['attributes.active' => ['required', 'boolean']];
    }

    public function index(Request $request)
    {
        $this->ensureAdmin($request);

        return parent::index($request);
    }

    public function show(Request $request, $id)
    {
        $this->ensureAdmin($request);

        return parent::show($request, $id);
    }

    public function update(Request $request, $id)
    {
        $this->ensureAdmin($request);
        $user = User::withTrashed()->findOrFail($id);
        $data = $this->validateResource($request, $this->type, $this->rules($request, $user));
        $active = filter_var($data['attributes']['active'], FILTER_VALIDATE_BOOLEAN);

        DB::transaction(function () use ($user, $active) {
            $worker = Worker::withTrashed()->where('user_id', $user->id)->first();

            if ($active) {
                $user->restore();
                $worker && $worker->restore();
            } else {
                $user->delete();
                $worker && $worker->delete();
                app(TokenService::class)->revokeAll($user->id);
            }
        });

        return JsonApiResponse::make((new Document($request))->resource(User::withTrashed()->find($user->id)));
    }

    protected function newQuery(Request $request): Builder
    {
        $query = User::query();
        $active = $request->input('filter.active');

        if ($active === 'false') {
            $query->onlyTrashed();
        } elseif ($active === 'all') {
            $query->withTrashed();
        }

        return $query;
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        if ($search = $parameters->filter('search')) {
            $query->where(function ($query) use ($search) {
                foreach (['username', 'first_name', 'middle_name', 'first_surname', 'second_surname'] as $column) {
                    $query->orWhere($column, 'like', '%'.$search.'%');
                }
            });
        }

        if ($parameters->filter('hasWorker') !== null) {
            $parameters->filter('hasWorker') === 'true' ? $query->has('worker') : $query->doesntHave('worker');
        }
    }

    private function ensureAdmin(Request $request): void
    {
        if (! $request->user()->isAdmin()) {
            throw new AuthorizationException();
        }
    }
}
