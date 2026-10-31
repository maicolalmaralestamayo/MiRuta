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
 * clave del ajuste; la Entidad es la del usuario, o filter[entity] para el
 * Administrador. Los cambia el Jefe de Transporte de esa Entidad (y el
 * Administrador); borrar uno vuelve al valor de la app.
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

        if ($user->isAdmin()) {
            if (! $requested || ! ctype_digit((string) $requested)) {
                throw JsonApiException::badRequest('Indica la Entidad con filter[entity].', 'filter[entity]');
            }

            return (int) $requested;
        }

        return (int) $user->entityId();
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
        if (! $request->user()->managesEntity($entityId)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el Jefe de Transporte de la Entidad cambia sus ajustes.');
        }
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
                'editable' => $request->user()->managesEntity($entityId),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
            ],
        ];
    }
}
