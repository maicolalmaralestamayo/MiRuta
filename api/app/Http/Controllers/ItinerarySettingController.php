<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Itinerary;
use App\Models\ItinerarySetting;
use App\Models\ItineraryStop;
use App\Models\ItineraryStopSetting;
use App\Models\SettingDefinition;
use App\Services\Permissions;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Ajustes por itinerario y por parada de un itinerario (docs/11 §11.17).
 * El id de cada recurso es la clave del ajuste.
 *
 * - itinerary-settings?filter[itinerary]=X: los marcados itinerary_level.
 * - itinerary-stop-settings?filter[itineraryStop]=X: los marcados stop_level
 *   (X es el id de la parada en el itinerario, recurso itinerary-stops).
 *
 * Los ven quienes ven el itinerario; los cambian (PATCH) y los devuelven al
 * valor heredado (DELETE) quienes tienen settings.itinerary sobre él.
 * Gana el más concreto: usuario → parada → itinerario → Entidad → app.
 */
class ItinerarySettingController extends Controller
{
    /** @var Settings */
    private $settings;

    /** @var Permissions */
    private $permissions;

    public function __construct(Settings $settings, Permissions $permissions)
    {
        $this->settings = $settings;
        $this->permissions = $permissions;
    }

    public function index(Request $request)
    {
        $itinerary = $this->itinerary($request);
        $custom = ItinerarySetting::where('itinerary_id', $itinerary->id)->pluck('setting_definition_id')->all();
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            if ($definition->itinerary_level) {
                $data[] = $this->itineraryResource($request, $definition, $itinerary, in_array($definition->id, $custom));
            }
        }

        return JsonApiResponse::make(Document::fromArray($data, ['itinerary' => (string) $itinerary->id]));
    }

    public function update(Request $request, string $id)
    {
        $itinerary = $this->itinerary($request);
        $definition = $this->definition($id, 'itinerary_level');
        $this->authorizeEdit($request, $itinerary);
        $data = $this->validateResource($request, 'itinerary-settings', ['attributes.value' => ['present']]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = ItinerarySetting::withTrashed()->firstOrNew(['itinerary_id' => $itinerary->id, 'setting_definition_id' => $definition->id]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();
        $this->settings->flush();

        return JsonApiResponse::make(Document::fromArray($this->itineraryResource($request, $definition, $itinerary, true)));
    }

    public function destroy(Request $request, string $id)
    {
        $itinerary = $this->itinerary($request);
        $definition = $this->definition($id, 'itinerary_level');
        $this->authorizeEdit($request, $itinerary);
        ItinerarySetting::where('itinerary_id', $itinerary->id)->where('setting_definition_id', $definition->id)->delete();
        $this->settings->flush();

        return response('', 204);
    }

    public function stopIndex(Request $request)
    {
        $itineraryStop = $this->itineraryStop($request);
        $custom = ItineraryStopSetting::where('itinerary_stop_id', $itineraryStop->id)->pluck('setting_definition_id')->all();
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            if ($definition->stop_level) {
                $data[] = $this->stopResource($request, $definition, $itineraryStop, in_array($definition->id, $custom));
            }
        }

        return JsonApiResponse::make(Document::fromArray($data, ['itineraryStop' => (string) $itineraryStop->id]));
    }

    public function stopUpdate(Request $request, string $id)
    {
        $itineraryStop = $this->itineraryStop($request);
        $definition = $this->definition($id, 'stop_level');
        $this->authorizeEdit($request, $itineraryStop->itinerary);
        $data = $this->validateResource($request, 'itinerary-stop-settings', ['attributes.value' => ['present']]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = ItineraryStopSetting::withTrashed()->firstOrNew(['itinerary_stop_id' => $itineraryStop->id, 'setting_definition_id' => $definition->id]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();
        $this->settings->flush();

        return JsonApiResponse::make(Document::fromArray($this->stopResource($request, $definition, $itineraryStop, true)));
    }

    public function stopDestroy(Request $request, string $id)
    {
        $itineraryStop = $this->itineraryStop($request);
        $definition = $this->definition($id, 'stop_level');
        $this->authorizeEdit($request, $itineraryStop->itinerary);
        ItineraryStopSetting::where('itinerary_stop_id', $itineraryStop->id)->where('setting_definition_id', $definition->id)->delete();
        $this->settings->flush();

        return response('', 204);
    }

    private function itineraryResource(Request $request, SettingDefinition $definition, Itinerary $itinerary, bool $isCustom): array
    {
        return [
            'type' => 'itinerary-settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->inheritedRaw($definition, (int) $itinerary->entity_id, (int) $itinerary->id),
                // Lo que vale si se quita el del itinerario: el de la Entidad o el de la app.
                'inheritedValue' => $this->settings->inheritedRaw($definition, (int) $itinerary->entity_id),
                'isCustom' => $isCustom,
                'editable' => $this->canEdit($request, $itinerary),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
                'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $itinerary->id]],
            ],
        ];
    }

    private function stopResource(Request $request, SettingDefinition $definition, ItineraryStop $itineraryStop, bool $isCustom): array
    {
        $itinerary = $itineraryStop->itinerary;

        return [
            'type' => 'itinerary-stop-settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->inheritedRaw($definition, (int) $itinerary->entity_id, (int) $itinerary->id, (int) $itineraryStop->stop_id),
                // Lo que vale si se quita el de la parada: el del itinerario, la Entidad o la app.
                'inheritedValue' => $this->settings->inheritedRaw($definition, (int) $itinerary->entity_id, (int) $itinerary->id),
                'isCustom' => $isCustom,
                'editable' => $this->canEdit($request, $itinerary),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
                'itineraryStop' => ['data' => ['type' => 'itinerary-stops', 'id' => (string) $itineraryStop->id]],
            ],
        ];
    }

    private function itinerary(Request $request): Itinerary
    {
        $id = $request->input('filter.itinerary');

        if (! $id || ! ctype_digit((string) $id)) {
            throw JsonApiException::badRequest('Indique el itinerario con filter[itinerary].', 'filter[itinerary]');
        }

        $itinerary = Itinerary::find($id);

        if (! $itinerary || ! $this->canView($request, $itinerary)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El itinerario no existe o no puede verlo.');
        }

        return $itinerary;
    }

    private function itineraryStop(Request $request): ItineraryStop
    {
        $id = $request->input('filter.itineraryStop');

        if (! $id || ! ctype_digit((string) $id)) {
            throw JsonApiException::badRequest('Indique la parada del itinerario con filter[itineraryStop].', 'filter[itineraryStop]');
        }

        $itineraryStop = ItineraryStop::with('itinerary')->find($id);

        if (! $itineraryStop || ! $itineraryStop->itinerary || ! $this->canView($request, $itineraryStop->itinerary)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La parada no existe o no puede verla.');
        }

        return $itineraryStop;
    }

    private function definition(string $key, string $level): SettingDefinition
    {
        $definition = $this->settings->definition($key);

        if (! $definition->{$level}) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "El ajuste \"{$key}\" no se puede cambiar a ese nivel.");
        }

        return $definition;
    }

    private function canView(Request $request, Itinerary $itinerary): bool
    {
        $user = $request->user();

        return $user->belongsToEntity($itinerary->entity_id)
            || $this->permissions->can($user, 'itineraries.view', (int) $itinerary->entity_id, (int) $itinerary->id)
            || $this->canEdit($request, $itinerary);
    }

    private function canEdit(Request $request, Itinerary $itinerary): bool
    {
        return $this->permissions->can($request->user(), 'settings.itinerary', (int) $itinerary->entity_id, (int) $itinerary->id);
    }

    private function authorizeEdit(Request $request, Itinerary $itinerary): void
    {
        if (! $this->canEdit($request, $itinerary)) {
            throw Permissions::forbidden('No puede cambiar los ajustes de este itinerario.');
        }
    }
}
