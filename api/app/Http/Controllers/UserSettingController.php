<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\SettingDefinition;
use App\Models\UserSetting;
use App\Models\User;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Ajustes del usuario autenticado. El id de cada recurso es la clave del ajuste.
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
        $user = $request->user();
        $custom = UserSetting::where('user_id', $user->id)->pluck('setting_definition_id')->all();
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            if ($definition->user_overridable) {
                $data[] = $this->resource($definition, $user, in_array($definition->id, $custom));
            }
        }

        return JsonApiResponse::make(Document::fromArray($data));
    }

    public function update(Request $request, string $id)
    {
        $definition = $this->overridable($id);
        $data = $this->validateResource($request, 'user-settings', [
            'attributes.value' => ['present'],
        ]);
        $user = $request->user();
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

    /**
     * Vuelve al valor de su Entidad (o al de la app).
     */
    public function destroy(Request $request, string $id)
    {
        $definition = $this->overridable($id);
        UserSetting::where('user_id', $request->user()->id)->where('setting_definition_id', $definition->id)->delete();

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
                // Lo que vale si quita el suyo: el de su Entidad o el de la app.
                'inheritedValue' => $this->settings->inheritedRaw($definition, $user->entityId()),
                'isCustom' => $isCustom,
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
            ],
        ];
    }
}
