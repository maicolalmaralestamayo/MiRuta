<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use App\JsonApi\QueryParameters;
use App\Models\User;
use App\Models\Worker;
use App\Services\Access;
use App\Services\Accounts;
use App\Support\IdentityCard;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Personas (recurso "users"). Cada uno ve a las personas de sus Entidades; el
 * Administrador, a todas (también a las que no tienen Entidad:
 * filter[entity]=none). Solo el Administrador las edita y elimina.
 */
class PersonController extends Controller
{
    public const SORTABLE = [
        'id' => 'id', 'firstName' => 'first_name', 'firstSurname' => 'first_surname',
        'secondSurname' => 'second_surname', 'username' => 'username', 'createdAt' => 'created_at',
    ];

    public function __construct(private Access $access)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['entity', 'itinerary', 'stop', 'search'], [], 'firstName,firstSurname,secondSurname');
        $query = $this->visible($request->user());

        foreach (['entity' => 'entity_id', 'itinerary' => 'itinerary_id', 'stop' => 'stop_id'] as $filter => $column) {
            $value = $parameters->filter($filter);

            if ($value === null) {
                continue;
            }

            if ($value === 'none' && $filter === 'entity') {
                $this->access->requireAdmin($request->user(), 'Solo el Administrador ve a las personas sin Entidad.');
                $query->whereNotIn('id', Worker::select('user_id'));
            } elseif ($value === 'none') {
                $query->whereIn('id', Worker::whereNull($column)->select('user_id'));
            } else {
                $query->whereIn('id', Worker::where($column, (int) $value)->select('user_id'));
            }
        }

        if ($search = $parameters->filter('search')) {
            self::search($query, $search);
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->visible($request->user())->findOrFail($id));
    }

    /**
     * Solo el Administrador: nombres, carné y usuario.
     */
    public function update(Request $request, Accounts $accounts, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador edita los datos de otras personas.');
        $user = User::findOrFail($id);
        $data = $this->validateResource($request, 'users', UserController::nameRules('attributes.', false) + [
            'attributes.identityCard' => ['sometimes', 'required', 'string', 'max:20'],
            'attributes.username' => ['sometimes', 'required', 'string', 'max:60'],
        ]);
        $attributes = $data['attributes'] ?? [];

        DB::transaction(function () use ($user, $attributes, $accounts) {
            if (array_key_exists('username', $attributes)) {
                $accounts->changeUsername($user, $attributes['username']);
            }

            if (array_key_exists('identityCard', $attributes)) {
                $accounts->changeIdentityCard($user, $attributes['identityCard']);
            }

            $user->fill(UserController::names($attributes))->save();
        });

        return $this->respond($request, $user->fresh());
    }

    /**
     * Solo el Administrador. Sin consecuencias para lo demás (docs/11 §11.22).
     */
    public function destroy(Request $request, $id)
    {
        $this->access->requireAdmin($request->user(), 'Solo el Administrador elimina personas.');
        $user = User::findOrFail($id);

        if ($user->isAdmin()) {
            throw JsonApiException::conflict('ADMIN_NOT_DELETABLE', 'No se puede eliminar al Administrador.');
        }

        $user->delete();
        $this->access->flush();

        return $this->noContent();
    }

    private function visible(User $viewer): Builder
    {
        $query = User::query();

        if (! $this->access->isAdmin($viewer)) {
            $query->where(fn ($q) => $q->where('id', $viewer->id)
                ->orWhereIn('id', Worker::whereIn('entity_id', $this->access->entityIds($viewer) ?: [0])->select('user_id')));
        }

        return $query;
    }

    /**
     * Busca por nombre, usuario o carné.
     */
    public static function search(Builder $query, string $text, string $userColumn = 'id'): void
    {
        $text = trim($text);
        $ids = User::query()->where(function ($q) use ($text) {
            foreach (preg_split('/\s+/u', $text) as $word) {
                $like = '%'.str_replace(['%', '_'], ['\%', '\_'], $word).'%';
                $q->where(fn ($w) => $w->where('first_name', 'like', $like)->orWhere('middle_name', 'like', $like)
                    ->orWhere('first_surname', 'like', $like)->orWhere('second_surname', 'like', $like)->orWhere('username', 'like', $like));
            }

            if (IdentityCard::isValid($text)) {
                $q->orWhere('identity_card_hash', IdentityCard::hash(IdentityCard::normalize($text)));
            }
        })->select('id');

        $query->whereIn($userColumn, $ids);
    }
}
