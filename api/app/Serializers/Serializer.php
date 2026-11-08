<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Convierte un modelo en un objeto de recurso JSON:API.
 */
abstract class Serializer
{
    /** Tipo de recurso JSON:API (plural, kebab-case). */
    abstract public function type(): string;

    public function id(Model $model): string
    {
        return (string) $model->getKey();
    }

    /** Atributos públicos del recurso, en camelCase. */
    abstract public function attributes(Model $model, Request $request): array;

    /**
     * Relaciones a uno: [nombre JSON:API => [tipo, columna de la clave foránea, método de la relación]].
     */
    public function toOneRelationships(): array
    {
        return [];
    }

    /** Datos calculados que no son atributos. */
    public function meta(Model $model, Request $request): array
    {
        return [];
    }

    public function selfLink(Model $model): string
    {
        return url('api/v1/'.$this->type().'/'.$this->id($model));
    }

    protected function date($value): ?string
    {
        return $value ? $value->toIso8601String() : null;
    }

    protected function day($value): ?string
    {
        return $value ? $value->toDateString() : null;
    }

    protected function image(?string $path): ?string
    {
        return $path ? url($path) : null;
    }
}
