<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\SettingDefinition;
use App\Models\UserSetting;
use App\Models\User;
use App\Services\Permissions;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Ajustes del usuario autenticado (me/settings) y, con settings.worker, los
 * de otro trabajador (users/{userId}/settings). El id de cada recurso es la
 * clave del ajuste.
 */
class UserSettingController extends Controller
{
    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    public function index(Request $request)
    {
        return $this->listFor($request->user());
    }

    public function update(Request $request, string $id)
    {
        return $this->updateSetting($request, $request->user(), $id);
    }

    /**
     * Vuelve al heredado (parada, itinerario, Entidad o app).
     */
    public function destroy(Request $request, string $id)
    {
        return $this->destroySetting($request->user(), $id);
    }

    public function indexFor(Request $request, $userId)
    {
        return $this->listFor($this->target($request, $userId));
    }

    public function updateFor(Request $request, $userId, string $id)
    {
        return $this->updateSetting($request, $this->target($request, $userId), $id);
    }

    public function destroyFor(Request $request, $userId, string $id)
    {
        return $this->destroySetting($this->target($request, $userId), $id);
    }

    /**
     * Persona cuyos ajustes se tocan: uno mismo o alguien sobre cuya
     * pertenencia (Entidad o itinerario) se tiene settings.worker.
     */
    private function target(Request $request, $userId): User
    {
        $viewer = $request->user();
        $user = User::find($userId);

        if (! $user) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La persona no existe.');
        }

        if ((int) $user->id === (int) $viewer->id) {
            return $user;
        }

        $permissions = app(Permissions::class);

        foreach ($user->activeWorkers() as $worker) {
            if ($permissions->can($viewer, 'settings.worker', (int) $worker->entity_id, $worker->itinerary_id ? (int) $worker->itinerary_id : null)) {
                return $user;
            }
        }

        if ($viewer->isAdmin()) {
            return $user;
        }

        throw Permissions::forbidden('No tiene permiso para cambiar los ajustes de esta persona.');
    }

    private function listFor(User $user)
    {
        $custom = UserSetting::where('user_id', $user->id)->pluck('setting_definition_id')->all();
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            if ($definition->user_overridable) {
                $data[] = $this->resource($definition, $user, in_array($definition->id, $custom));
            }
        }

        return JsonApiResponse::make(Document::fromArray($data));
    }

    private function updateSetting(Request $request, User $user, string $id)
    {
        $definition = $this->overridable($id);
        $data = $this->validateResource($request, 'user-settings', [
            'attributes.value' => ['present'],
        ]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = UserSetting::withTrashed()->firstOrNew([
            'user_id' => $user->id,
            'setting_definition_id' => $definition->id,
        ]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();

        return JsonApiResponse::make(Document::fromArray($this->resource($definition, $user, true)));
    }

    private function destroySetting(User $user, string $id)
    {
        $definition = $this->overridable($id);
        UserSetting::where('user_id', $user->id)->where('setting_definition_id', $definition->id)->delete();

        return response('', 204);
    }

    private function overridable(string $key): SettingDefinition
    {
        $definition = $this->settings->definition($key);

        if (! $definition->user_overridable) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "El ajuste \"{$key}\" no se puede personalizar.");
        }

        return $definition;
    }

    private function resource(SettingDefinition $definition, User $user, bool $isCustom): array
    {
        return [
            'type' => 'user-settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->effectiveRaw($definition, $user),
                // Lo que vale si quita el suyo: el de su Entidad (si pertenece a una sola) o el de la app.
                'inheritedValue' => $this->settings->inheritedRaw($definition, $user->singleEntityId()),
                'isCustom' => $isCustom,
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
                'user' => ['data' => ['type' => 'users', 'id' => (string) $user->id]],
            ],
        ];
    }
}
