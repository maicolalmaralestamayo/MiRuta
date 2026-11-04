<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Entity;
use App\Models\Worker;
use App\Models\WorkerRole;
use App\Services\Accounts;
use App\Services\Memberships;
use App\Services\Permissions;
use App\Services\Passwords;
use App\Services\Settings;
use App\Services\TokenService;
use App\Services\Uploads;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * La persona propia (recurso "users"), sus Entidades y sus permisos.
 */
class MeController extends Controller
{
    /**
     * meta.permissions: [{operation, scope, entityId, itineraryId}];
     * meta.memberships: sus Entidades con itinerario, parada y roles.
     */
    public function show(Request $request)
    {
        return $this->respond($request, $request->user()->refreshMemberships());
    }

    /**
     * Usuario, nombres, carné y contraseña.
     *
     * Cambiar la contraseña exige la actual (meta.currentPassword), salvo
     * tras recuperar el acceso; cierra las demás sesiones.
     */
    public function update(Request $request, Accounts $accounts, Passwords $passwords, TokenService $tokens)
    {
        $data = $this->validateResource($request, 'users', UserController::nameRules('attributes.', false) + [
            'attributes.identityCard' => ['sometimes', 'required', 'string', 'max:20'],
            'attributes.username' => ['sometimes', 'required', 'string', 'max:60'],
            'attributes.password' => ['sometimes', 'required', 'string'],
        ]);

        $user = $request->user();
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];

        DB::transaction(function () use ($request, $user, $attributes, $accounts, $passwords, $tokens) {
            if (array_key_exists('username', $attributes)) {
                $accounts->changeUsername($user, $attributes['username']);
            }

            if (array_key_exists('identityCard', $attributes)) {
                $accounts->changeIdentityCard($user, $attributes['identityCard']);
            }

            $user->fill(UserController::names($attributes));
            $user->save();

            if (array_key_exists('password', $attributes)) {
                $this->changePassword($request, $user, $attributes['password'], $passwords, $tokens);
            }
        });

        return $this->respond($request, $user->fresh());
    }

    /**
     * El Administrador entra en una Entidad sin solicitud (docs/11 §11.13):
     * relationships.entity o attributes.entityAbbreviation.
     */
    public function joinEntity(Request $request, Accounts $accounts, Memberships $memberships)
    {
        $user = $request->user();

        if (! $user->isAdmin()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso',
                'Solo el Administrador entra directamente en una Entidad. Los demás lo solicitan (applications, entity_membership).');
        }

        $data = $this->validateResource($request, 'workers', [
            'attributes.entityAbbreviation' => ['sometimes', 'string', 'max:15'],
            'relationships.entity.data.type' => ['required_without:data.attributes.entityAbbreviation', 'in:entities'],
            'relationships.entity.data.id' => ['required_without:data.attributes.entityAbbreviation', 'exists:entities,id,deleted_at,NULL'],
        ]);
        $entity = isset($data['relationships']['entity']['data']['id'])
            ? Entity::findOrFail($data['relationships']['entity']['data']['id'])
            : $accounts->entityOrFail($data['attributes']['entityAbbreviation']);

        $worker = $memberships->join($user, $entity, $user);

        return JsonApiResponse::make((new Document($request))->resource($worker->fresh(), ['entity']), 201, [
            'Location' => url('api/v1/workers/'.$worker->id),
        ]);
    }

    /**
     * Darse de baja de una Entidad (docs/11 §11.6).
     */
    public function leaveEntity(Request $request, Memberships $memberships, $entityId)
    {
        $worker = $request->user()->workerIn($entityId);

        if (! $worker) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'No pertenece a esa Entidad.');
        }

        $memberships->leave($worker, $request->user());

        return response('', 204);
    }

    private function respond(Request $request, $user)
    {
        $document = (new Document($request))->resource($user);
        $document['data']['meta'] = array_merge(isset($document['data']['meta']) ? $document['data']['meta'] : [], [
            'permissions' => app(Permissions::class)->forUser($user),
            'memberships' => self::memberships($user),
        ]);

        return JsonApiResponse::make($document);
    }

    /**
     * Sus Entidades (pertenencias) con itinerario, parada y roles.
     */
    public static function memberships($user): array
    {
        $workers = Worker::where('user_id', $user->id)->with('entity', 'itinerary', 'stop')->orderBy('id')->get();
        $roles = WorkerRole::whereIn('worker_id', $workers->pluck('id'))->with('role', 'itinerary')->get()->groupBy('worker_id');
        $image = function ($path) {
            return $path ? url($path) : null;
        };

        return $workers->map(function (Worker $worker) use ($roles, $image) {
            $entity = $worker->entity;
            $itinerary = $worker->itinerary;
            $stop = $worker->stop;

            return [
                'workerId' => (string) $worker->id,
                'entity' => [
                    'id' => (string) $entity->id,
                    'abbreviation' => $entity->abbreviation,
                    'name' => $entity->name,
                    'imageUrl' => $image($entity->image_path),
                    'workerCount' => Worker::where('entity_id', $entity->id)->count(),
                ],
                'itinerary' => $itinerary ? [
                    'id' => (string) $itinerary->id,
                    'name' => $itinerary->name,
                    'imageUrl' => $image($itinerary->image_path),
                    'memberCount' => Worker::where('itinerary_id', $itinerary->id)->count(),
                ] : null,
                'stop' => $stop ? [
                    'id' => (string) $stop->id,
                    'landmark' => $stop->landmark,
                    'street' => $stop->street,
                    'imageUrl' => $image($stop->image_path),
                ] : null,
                'roles' => (isset($roles[$worker->id]) ? $roles[$worker->id] : collect())->filter(function (WorkerRole $workerRole) {
                    return $workerRole->role && ! $workerRole->role->trashed();
                })->map(function (WorkerRole $workerRole) {
                    return [
                        'id' => (string) $workerRole->id,
                        'roleId' => (string) $workerRole->role_id,
                        'name' => $workerRole->role->name,
                        'icon' => $workerRole->role->icon,
                        'isDefault' => (bool) $workerRole->role->is_default,
                        'itineraryId' => $workerRole->itinerary_id ? (string) $workerRole->itinerary_id : null,
                        'itineraryName' => $workerRole->itinerary ? $workerRole->itinerary->name : null,
                    ];
                })->values()->all(),
            ];
        })->all();
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->validate($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('photo_max_kb')],
        ]);

        $user = $request->user();
        $previous = $user->photo_path;
        $user->photo_path = $uploads->store($request->file('photo'), 'photos');
        $user->save();
        $uploads->delete($previous);

        return $this->respond($request, $user);
    }

    public function deletePhoto(Request $request, Uploads $uploads)
    {
        $user = $request->user();
        $uploads->delete($user->photo_path);
        $user->photo_path = null;
        $user->save();

        return response('', 204);
    }

    private function changePassword(Request $request, $user, string $password, Passwords $passwords, TokenService $tokens): void
    {
        $recovering = (bool) $user->must_change_password;

        // Tras recuperar el acceso no se conoce la actual.
        if (! $recovering) {
            $current = $request->json('meta.currentPassword');

            if (! is_string($current) || ! $user->password || ! Hash::check($current, $user->password)) {
                throw new JsonApiException(422, 'CURRENT_PASSWORD_INVALID', 'Contraseña actual incorrecta',
                    'Para cambiar la contraseña hay que enviar la actual en meta.currentPassword.', ['pointer' => '/meta/currentPassword']);
            }
        }

        $passwords->validate($password, [$user->username, $user->first_name, $user->middle_name, $user->first_surname, $user->second_surname], $user);
        $passwords->set($user, $password);

        // La sesión actual sigue abierta; las demás se cierran.
        $current = $user->currentSessionId();
        \App\Models\RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')
            ->when($current !== null, function ($query) use ($current) {
                $query->where('id', '<>', $current);
            })
            ->update(['revoked_at' => \Carbon\Carbon::now()]);
    }
}
