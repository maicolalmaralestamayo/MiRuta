<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * El id de una definición es su clave (estable entre instalaciones).
 */
class SettingDefinitionSerializer extends Serializer
{
    public function type(): string
    {
        return 'setting-definitions';
    }

    public function id(Model $definition): string
    {
        return $definition->key;
    }

    public function attributes(Model $definition, Request $request): array
    {
        return [
            'key' => $definition->key,
            'name' => $definition->name,
            'description' => $definition->description,
            'valueType' => $definition->value_type,
            'defaultValue' => $definition->default_value,
            'minValue' => $definition->min_value,
            'maxValue' => $definition->max_value,
            'minSetting' => $definition->minSettingDefinition ? $definition->minSettingDefinition->key : null,
            'level' => $definition->level,
            'userOverridable' => $definition->user_overridable,
            'options' => $definition->options->map(function ($option) {
                return ['value' => $option->value, 'name' => $option->name];
            })->values()->all(),
        ];
    }
}
