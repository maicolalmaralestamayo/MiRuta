<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\Setting;
use App\Models\SettingDefinition;
use App\Models\Worker;
use App\Services\Settings;
use Illuminate\Http\Request;

/**
 * Valores globales de los ajustes. El id es la clave del ajuste. Cada uno lo
 * cambia quien indique editable_by (el Administrador siempre).
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
        $worker = $request->user();

        if (! $this->canEdit($definition, $worker)) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No puedes cambiar este ajuste.');
        }

        $data = $this->validateResource($request, 'settings', ['attributes.value' => ['present']]);
        $value = $this->settings->normalize($definition, $data['attributes']['value']);

        $setting = Setting::withTrashed()->firstOrNew(['setting_definition_id' => $definition->id]);
        $setting->value = $value;
        $setting->deleted_at = null;
        $setting->save();
        $this->settings->flush();

        return JsonApiResponse::make(Document::fromArray($this->resource($this->settings->definition($id), $worker)));
    }

    private function canEdit(SettingDefinition $definition, Worker $worker): bool
    {
        if ($worker->isAdmin()) {
            return true;
        }

        return $definition->editable_by === 'transport_chief' && $worker->isTransportChief();
    }

    private function resource(SettingDefinition $definition, Worker $worker): array
    {
        return [
            'type' => 'settings',
            'id' => $definition->key,
            'attributes' => [
                'value' => $this->settings->effectiveRaw($definition),
                'editable' => $this->canEdit($definition, $worker),
            ],
            'relationships' => [
                'definition' => ['data' => ['type' => 'setting-definitions', 'id' => $definition->key]],
            ],
        ];
    }
}
