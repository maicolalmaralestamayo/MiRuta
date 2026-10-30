<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Capa de "vista" del patrón modelo-controlador: convierte un modelo en un
 * objeto de recurso JSON:API.
 */
abstract class Serializer
{
    /**
     * Tipo de recurso JSON:API (plural, kebab-case).
     */
    abstract public function type(): string;

    /**
     * Atributos públicos del recurso, en camelCase.
     */
    abstract public function attributes(Model $model, Request $request): array;

    /**
     * Relaciones a uno: [nombre JSON:API => [tipo, columna de la clave foránea, método de la relación]].
     */
    public function toOneRelationships(): array
    {
        return [];
    }

    /**
     * Datos calculados que no son atributos.
     */
    public function meta(Model $model, Request $request): array
    {
        return [];
    }

    public function selfLink(Model $model): string
    {
        return url('api/v1/'.$this->type().'/'.$model->getKey());
    }

    /**
     * Formatea una fecha en ISO 8601 con zona horaria.
     */
    protected function date($value): ?string
    {
        return $value ? $value->toIso8601String() : null;
    }
}
