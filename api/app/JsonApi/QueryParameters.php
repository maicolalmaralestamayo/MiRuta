<?php

namespace App\JsonApi;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

/**
 * Lee y valida los parámetros de consulta de JSON:API: page, sort, filter e include.
 * Cualquier valor no permitido produce un error 400 que señala el parámetro.
 */
class QueryParameters
{
    /** @var int */
    private $pageNumber = 1;

    /** @var int */
    private $pageSize;

    /** @var array [campo de la API => dirección] */
    private $sort = [];

    /** @var array [nombre => valor] */
    private $filters = [];

    /** @var string[] */
    private $includes = [];

    /**
     * @param array $sortable    [campo de la API => columna]
     * @param array $filterable  nombres de filtro admitidos
     * @param array $includable  rutas de relaciones admitidas (p. ej. "rank")
     * @param string|null $defaultSort  valor de sort cuando no se envía
     */
    public static function fromRequest(Request $request, array $sortable = [], array $filterable = [], array $includable = [], ?string $defaultSort = null): self
    {
        $parameters = new self();
        $parameters->readPage($request);
        $parameters->readSort($request->query('sort', $defaultSort), $sortable);
        $parameters->readFilters($request->query('filter', []), $filterable);
        $parameters->includes = self::readIncludes($request, $includable);

        return $parameters;
    }

    /**
     * Valida solo el parámetro include (para respuestas de un único recurso).
     *
     * @return string[]
     */
    public static function readIncludes(Request $request, array $includable): array
    {
        $value = $request->query('include');

        if ($value === null || $value === '') {
            return [];
        }

        if (! is_string($value)) {
            throw JsonApiException::badRequest('El parámetro include debe ser una lista separada por comas.', 'include');
        }

        $includes = array_values(array_unique(array_map('trim', explode(',', $value))));

        foreach ($includes as $include) {
            if (! in_array($include, $includable, true)) {
                throw JsonApiException::badRequest("No se puede incluir la relación \"{$include}\".", 'include');
            }
        }

        return $includes;
    }

    public function pageNumber(): int
    {
        return $this->pageNumber;
    }

    public function pageSize(): int
    {
        return $this->pageSize;
    }

    public function includes(): array
    {
        return $this->includes;
    }

    public function filters(): array
    {
        return $this->filters;
    }

    public function filter(string $name, $default = null)
    {
        return array_key_exists($name, $this->filters) ? $this->filters[$name] : $default;
    }

    /**
     * Aplica el orden a la consulta.
     *
     * @param array $sortable [campo de la API => columna]
     */
    public function applySort(Builder $query, array $sortable): Builder
    {
        foreach ($this->sort as $field => $direction) {
            $query->orderBy($sortable[$field], $direction);
        }

        return $query;
    }

    private function readPage(Request $request): void
    {
        $page = $request->query('page', []);
        $maxSize = (int) config('mitransporte.pagination.max_size');
        $this->pageSize = (int) config('mitransporte.pagination.default_size');

        if (! is_array($page)) {
            throw JsonApiException::badRequest('El parámetro page debe usarse como page[number] y page[size].', 'page');
        }

        if (array_key_exists('number', $page)) {
            $this->pageNumber = $this->positiveInteger($page['number'], 'page[number]');
        }

        if (array_key_exists('size', $page)) {
            $this->pageSize = $this->positiveInteger($page['size'], 'page[size]');

            if ($this->pageSize > $maxSize) {
                throw JsonApiException::badRequest("page[size] no puede ser mayor que {$maxSize}.", 'page[size]');
            }
        }
    }

    private function readSort($value, array $sortable): void
    {
        if ($value === null || $value === '') {
            return;
        }

        if (! is_string($value)) {
            throw JsonApiException::badRequest('El parámetro sort debe ser una lista separada por comas.', 'sort');
        }

        foreach (array_map('trim', explode(',', $value)) as $field) {
            $direction = 'asc';

            if (substr($field, 0, 1) === '-') {
                $direction = 'desc';
                $field = substr($field, 1);
            }

            if (! array_key_exists($field, $sortable)) {
                throw JsonApiException::badRequest("No se puede ordenar por \"{$field}\".", 'sort');
            }

            $this->sort[$field] = $direction;
        }
    }

    private function readFilters($value, array $filterable): void
    {
        if (! is_array($value)) {
            throw JsonApiException::badRequest('Los filtros deben usarse como filter[nombre]=valor.', 'filter');
        }

        foreach ($value as $name => $filterValue) {
            if (! in_array($name, $filterable, true)) {
                throw JsonApiException::badRequest("No existe el filtro \"{$name}\".", "filter[{$name}]");
            }

            if (! is_string($filterValue)) {
                throw JsonApiException::badRequest("El filtro \"{$name}\" debe tener un único valor.", "filter[{$name}]");
            }

            $this->filters[$name] = $filterValue;
        }
    }

    private function positiveInteger($value, string $parameter): int
    {
        if (! is_string($value) || ! ctype_digit($value) || (int) $value < 1) {
            throw JsonApiException::badRequest("{$parameter} debe ser un número entero mayor que 0.", $parameter);
        }

        return (int) $value;
    }
}
