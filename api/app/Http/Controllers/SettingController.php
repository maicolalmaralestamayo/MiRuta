<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Setting;
use App\Models\SettingDefinition;
use App\Models\User;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Valores de los ajustes para toda la app. El id es la clave del ajuste.
 * Los cambia quien tiene settings.app; los de nivel Entidad, por Entidad,
 * quien tiene settings.entity (EntitySettingController); por itinerario y
 * parada, settings.itinerary (ItinerarySettingController).
 */
class SettingController extends Controller
{
    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    public function index(Request $request)
    {
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            $data[] = $this->resource($definition, $request->user());
        }

        return JsonApiResponse::make(Document::fromArray($data));
    }

    public function show(Request $request, string $id)
    {
        return JsonApiResponse::make(Document::fromArray($this->resource($this->settings->definition($id), $request->user())));
    }

    public function update(Request $request, string $id)
    {
        $definition = $this->settings->definition($id);
        $user = $request->user();

        app(\App\Services\Permissions::class)->authorize($user, 'settings.app', null, null, 'No puede cambiar este ajuste.');

        $data = $this->validateResource($request, 'settings', ['attributes.value' => ['present']]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = Setting::withTrashed()->firstOrNew(['setting_definition_id' => $definition->id]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();
        $this->settings->flush();

        return JsonApiResponse::make(Document::fromArray($this->resource($this->settings->definition($id), $user)));
    }

    private function resource(SettingDefinition $definition, User $user): array
    {
        return [
            'type' => 'settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->effectiveRaw($definition),
                'editable' => app(\App\Services\Permissions::class)->can($user, 'settings.app'),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
            ],
        ];
    }
}
