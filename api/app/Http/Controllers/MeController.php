<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\RefreshToken;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerItinerary;
use App\Serializers\WorkerItinerarySerializer;
use App\Services\Access;
use App\Services\Accounts;
use App\Services\Applications;
use App\Services\Passwords;
use App\Services\Settings;
use App\Services\Uploads;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * La persona propia: perfil, contraseña, foto, rol y sus Entidades.
 */
class MeController extends Controller
{
    /**
     * meta.role (administrador, jefe o trabajador), meta.chiefItineraryId y
     * meta.memberships (sus Entidades, cada una con sus itinerarios y paradas).
     */
    public function show(Request $request)
    {
        return $this->respondMe($request, $request->user());
    }

    /**
     * Usuario, nombres, carné y contraseña. Cambiar la contraseña exige la
     * actual (meta.currentPassword), salvo si la puso otra persona; cierra las
     * demás sesiones.
     */
    public function update(Request $request, Accounts $accounts, Passwords $passwords)
    {
        $data = $this->validateResource($request, 'users', UserController::nameRules('attributes.', false) + [
            'attributes.identityCard' => ['sometimes', 'required', 'string', 'max:20'],
            'attributes.username' => ['sometimes', 'required', 'string', 'max:60'],
            'attributes.password' => ['sometimes', 'required', 'string'],
        ]);
        $user = $request->user();
        $attributes = $data['attributes'] ?? [];

        DB::transaction(function () use ($request, $user, $attributes, $accounts, $passwords) {
            if (array_key_exists('username', $attributes)) {
                $accounts->changeUsername($user, $attributes['username']);
            }

            if (array_key_exists('identityCard', $attributes)) {
                $accounts->changeIdentityCard($user, $attributes['identityCard']);
            }

            $user->fill(UserController::names($attributes));
            $user->save();

            if (array_key_exists('password', $attributes)) {
                $this->changePassword($request, $user, $attributes['password'], $passwords);
            }
        });

        return $this->respondMe($request, $user->fresh());
    }

    public function uploadPhoto(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->validateRequest($request, [
            'photo' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('tamano_foto')],
        ]);
        $user = $request->user();
        $previous = $user->photo_path;
        $user->photo_path = $uploads->store($request->file('photo'), 'photos');
        $user->save();
        $uploads->delete($previous);

        return $this->respondMe($request, $user);
    }

    public function deletePhoto(Request $request, Uploads $uploads)
    {
        $user = $request->user();
        $uploads->delete($user->photo_path);
        $user->photo_path = null;
        $user->save();

        return $this->noContent();
    }

    /**
     * Abrió la sección Solicitudes: sus solicitudes resueltas quedan vistas.
     */
    public function applicationsSeen(Request $request, Applications $applications)
    {
        $applications->markSeen($request->user());

        return $this->noContent();
    }

    private function respondMe(Request $request, User $user)
    {
        $access = app(Access::class);
        $access->flush($user->id);
        $document = (new Document($request))->resource($user);
        $document['data']['meta'] = [
            'role' => $access->roleOf($user),
            'chiefItineraryId' => $access->chiefItineraryId($user) ? (string) $access->chiefItineraryId($user) : null,
            'memberships' => self::memberships($user),
        ];

        return JsonApiResponse::make($document);
    }

    /**
     * Sus Entidades, cada una con sus itinerarios y la parada de cada uno
     * (Inicio y formulario del Trabajador; docs/11 §11.58 y §11.60).
     *
     * @param int[]|null $entityIds Solo esas Entidades (null = todas)
     */
    public static function memberships(User $user, ?array $entityIds = null): array
    {
        $image = fn ($path) => $path ? url($path) : null;

        return Worker::where('user_id', $user->id)->with('entity')->orderBy('id')
            ->when($entityIds !== null, fn ($q) => $q->whereIn('entity_id', $entityIds ?: [0]))
            ->get()->map(fn (Worker $worker) => [
                'workerId' => (string) $worker->id,
                'active' => (bool) $worker->active,
                'entity' => [
                    'id' => (string) $worker->entity_id,
                    'abbreviation' => $worker->entity->abbreviation,
                    'name' => $worker->entity->name,
                    'imageUrl' => $image($worker->entity->image_path),
                    'active' => (bool) $worker->entity->active,
                    'workerCount' => Worker::where('entity_id', $worker->entity_id)->count(),
                ],
                'itineraries' => WorkerItinerary::where('worker_id', $worker->id)->with('itinerary', 'stop')->orderBy('id')->get()
                    ->map(fn (WorkerItinerary $p) => WorkerItinerarySerializer::summary($p))->values()->all(),
            ])->all();
    }

    private function changePassword(Request $request, User $user, string $password, Passwords $passwords): void
    {
        // Si la puso otra persona no se conoce la actual.
        if (! $user->must_change_password) {
            $current = $request->json('meta.currentPassword');

            if (! is_string($current) || ! Hash::check($current, $user->password)) {
                throw new JsonApiException(422, 'CURRENT_PASSWORD_INVALID', 'Contraseña actual incorrecta',
                    'Para cambiar la contraseña hay que enviar la actual en meta.currentPassword.', ['pointer' => '/meta/currentPassword']);
            }
        }

        $passwords->validate($password, [$user->username, $user->first_name, $user->middle_name, $user->first_surname, $user->second_surname], $user);
        $passwords->set($user, $password);

        // La sesión actual sigue abierta; las demás se cierran.
        RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')
            ->when($user->currentSessionId() !== null, fn ($q) => $q->where('id', '<>', $user->currentSessionId()))
            ->update(['revoked_at' => Carbon::now()]);
    }
}
