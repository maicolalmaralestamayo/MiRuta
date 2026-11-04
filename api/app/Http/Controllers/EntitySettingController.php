<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\EntitySetting;
use App\Models\SettingDefinition;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Valores de los ajustes de nivel Entidad para una Entidad. El id es la
 * clave del ajuste; la Entidad es filter[entity] (o la única a la que
 * pertenece). Los cambia quien tiene settings.entity en ella; borrar uno
 * vuelve al valor de la app.
 */
class EntitySettingController extends Controller
{
    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    public function index(Request $request)
    {
        $entityId = $this->entityId($request);
        $custom = EntitySetting::where('entity_id', $entityId)->pluck('setting_definition_id')->all();
        $data = [];

        foreach ($this->settings->definitions() as $definition) {
            if ($definition->level === SettingDefinition::LEVEL_ENTITY) {
                $data[] = $this->resource($request, $definition, $entityId, in_array($definition->id, $custom));
            }
        }

        return JsonApiResponse::make(Document::fromArray($data, ['entity' => (string) $entityId]));
    }

    public function update(Request $request, string $id)
    {
        $entityId = $this->entityId($request);
        $definition = $this->entityDefinition($id);
        $this->ensureCanEdit($request, $entityId);
        $data = $this->validateResource($request, 'entity-settings', ['attributes.value' => ['present']]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = EntitySetting::withTrashed()->firstOrNew(['entity_id' => $entityId, 'setting_definition_id' => $definition->id]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();
        $this->settings->flush();

        return JsonApiResponse::make(Document::fromArray($this->resource($request, $definition, $entityId, true)));
    }

    public function destroy(Request $request, string $id)
    {
        $entityId = $this->entityId($request);
        $definition = $this->entityDefinition($id);
        $this->ensureCanEdit($request, $entityId);
        EntitySetting::where('entity_id', $entityId)->where('setting_definition_id', $definition->id)->delete();
        $this->settings->flush();

        return response('', 204);
    }

    private function entityId(Request $request): int
    {
        $user = $request->user();
        $requested = $request->input('filter.entity');

        if ($requested === null && $user->singleEntityId() !== null) {
            return $user->singleEntityId();
        }

        if (! $requested || ! ctype_digit((string) $requested)) {
            throw JsonApiException::badRequest('Indique la Entidad con filter[entity].', 'filter[entity]');
        }

        $permissions = app(\App\Services\Permissions::class);

        if (! $user->belongsToEntity($requested) && ! $permissions->can($user, 'settings.entity', (int) $requested)
            && ! $permissions->canInEntity($user, 'settings.itinerary', (int) $requested)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La Entidad no existe o no puede verla.');
        }

        return (int) $requested;
    }

    private function entityDefinition(string $key): SettingDefinition
    {
        $definition = $this->settings->definition($key);

        if ($definition->level !== SettingDefinition::LEVEL_ENTITY) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "El ajuste \"{$key}\" es de toda la app.");
        }

        return $definition;
    }

    private function ensureCanEdit(Request $request, int $entityId): void
    {
        app(\App\Services\Permissions::class)->authorize($request->user(), 'settings.entity', $entityId, null, 'No puede cambiar los ajustes de esta Entidad.');
    }

    private function resource(Request $request, SettingDefinition $definition, int $entityId, bool $isCustom): array
    {
        return [
            'type' => 'entity-settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->inheritedRaw($definition, $entityId),
                'appValue' => $this->settings->inheritedRaw($definition, null),
                'isCustom' => $isCustom,
                'editable' => app(\App\Services\Permissions::class)->can($request->user(), 'settings.entity', $entityId),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
            ],
        ];
    }
}
