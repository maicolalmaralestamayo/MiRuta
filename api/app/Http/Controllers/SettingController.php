<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Services\Access;
use App\Services\Settings;
use App\Support\SettingCatalog;
use Illuminate\Http\Request;

/**
 * Ajustes de la app (un solo nivel; docs/11 §11.38, §11.40 y §11.44). Todos los
 * leen (la app los necesita); solo el Administrador los cambia. El id es la clave.
 *
 * attributes.value es el texto con unidades («10min», «1km200m», «10km/hor») y
 * attributes.base, el valor en segundos, metros, metros por segundo o entero.
 */
class SettingController extends Controller
{
    public function __construct(private Settings $settings)
    {
    }

    public function index(Request $request)
    {
        $group = $request->input('filter.group');
        $resources = [];

        foreach (array_keys(SettingCatalog::SETTINGS) as $key) {
            if ($group === null || SettingCatalog::SETTINGS[$key][0] === $group) {
                $resources[] = $this->resource($key);
            }
        }

        return JsonApiResponse::make(Document::fromArray($resources, [
            'groups' => array_map(fn ($key, $name) => ['key' => $key, 'name' => $name], array_keys(SettingCatalog::GROUPS), SettingCatalog::GROUPS),
            'version' => $this->settings->version(),
        ]));
    }

    public function show($id)
    {
        if (! SettingCatalog::has($id)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "No existe el ajuste \"{$id}\".");
        }

        return JsonApiResponse::make(Document::fromArray($this->resource($id)));
    }

    /**
     * attributes.value con el formato de su tipo; null vuelve al valor por omisión.
     */
    public function update(Request $request, Access $access, $id)
    {
        $access->requireAdmin($request->user(), 'Solo el Administrador cambia los ajustes de la app.');

        if (! SettingCatalog::has($id)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', "No existe el ajuste \"{$id}\".");
        }

        $data = $this->validateResource($request, 'settings', ['attributes' => ['required', 'array']]);

        if (! array_key_exists('value', $data['attributes'])) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta el valor', 'Indique attributes.value.', ['pointer' => '/data/attributes/value']);
        }

        $value = $data['attributes']['value'];

        if ($value === null) {
            \App\Models\Setting::where('key', $id)->delete();
            $this->settings->flush();
        } else {
            $this->settings->set($id, $this->settings->normalize($id, $value));
        }

        return JsonApiResponse::make(Document::fromArray($this->resource($id)));
    }

    private function resource(string $key): array
    {
        $definition = SettingCatalog::definition($key);

        return [
            'type' => 'settings',
            'id' => $key,
            'attributes' => [
                'name' => $definition['name'],
                'group' => $definition['group'],
                'groupName' => $definition['groupName'],
                'type' => $definition['type'],
                'value' => $this->settings->raw($key),
                'base' => $this->settings->value($key),
                'baseUnit' => match ($definition['type']) {
                    SettingCatalog::TYPE_DURATION => 'seg',
                    SettingCatalog::TYPE_DISTANCE => 'm',
                    SettingCatalog::TYPE_SPEED => 'm/seg',
                    default => $definition['unit'],
                },
                'defaultValue' => (string) $definition['default'],
                'min' => (string) $definition['min'],
                'max' => (string) $definition['max'],
                'description' => $definition['description'],
            ],
            'links' => ['self' => url('api/v1/settings/'.$key)],
        ];
    }
}
