<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

abstract class Controller
{
    /**
     * Comprueba la estructura de un documento JSON:API de entrada y valida sus
     * atributos y relaciones. Las reglas se escriben con las claves de JSON:API
     * ("attributes.name", "relationships.itinerary.data.id") y los errores se
     * devuelven con source.pointer = /data/attributes/name.
     *
     * @return array El objeto "data" validado.
     */
    protected function validateResource(Request $request, string $type, array $rules): array
    {
        $data = $request->json('data');

        if (! is_array($data) || array_is_list($data) && $data !== []) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Petición incorrecta', 'El documento debe tener un objeto "data".', ['pointer' => '/data']);
        }

        if (! isset($data['type']) || $data['type'] !== $type) {
            throw JsonApiException::conflict('TYPE_MISMATCH', "El tipo del recurso debe ser \"{$type}\".", '/data/type');
        }

        $prefixed = [];

        foreach ($rules as $key => $keyRules) {
            $prefixed['data.'.$key] = array_map(function ($rule) {
                return is_string($rule) ? preg_replace('/^(required_with|required_without|required_if|prohibited_unless):(?!data\.)/', '$1:data.', $rule) : $rule;
            }, (array) $keyRules);
        }

        Validator::make(['data' => $data], $prefixed)->validate();

        return $data;
    }

    /**
     * Valida los campos de la petición (formularios multipart y parámetros).
     */
    protected function validateRequest(Request $request, array $rules): array
    {
        return Validator::make($request->all(), $rules)->validate();
    }

    protected function validateQuery(Request $request, array $rules): array
    {
        return Validator::make($request->query(), $rules)->validate();
    }

    /**
     * Id de una relación a uno del documento (o null).
     */
    protected function relationshipId(array $data, string $name): ?int
    {
        $id = $data['relationships'][$name]['data']['id'] ?? null;

        return $id === null ? null : (int) $id;
    }

    protected function hasRelationship(array $data, string $name): bool
    {
        return isset($data['relationships'][$name]) && array_key_exists('data', $data['relationships'][$name]);
    }

    /**
     * Reglas de una relación a uno: tipo correcto e id existente.
     */
    protected function relationshipRules(string $name, string $type, string $table, bool $required, bool $nullable = false): array
    {
        $presence = $required ? 'required' : 'sometimes';

        return [
            "relationships.{$name}" => [$presence, 'array'],
            "relationships.{$name}.data" => $nullable ? ["present_with:data.relationships.{$name}", 'nullable', 'array'] : [$presence, 'array'],
            "relationships.{$name}.data.type" => ["required_with:data.relationships.{$name}.data", "in:{$type}"],
            "relationships.{$name}.data.id" => ["required_with:data.relationships.{$name}.data", "exists:{$table},id"],
        ];
    }

    protected function respond(Request $request, Model $model, array $includes = [], int $status = 200, array $headers = [])
    {
        return JsonApiResponse::make((new Document($request))->resource($model, $includes), $status, $headers);
    }

    protected function created(Request $request, Model $model, string $type, array $includes = [])
    {
        return $this->respond($request, $model, $includes, 201, ['Location' => url('api/v1/'.$type.'/'.$model->getKey())]);
    }

    /**
     * Lista paginada con orden, filtros (ya aplicados en $query) e include.
     */
    protected function paginate(Request $request, Builder $query, QueryParameters $parameters, array $sortable)
    {
        $paginator = $parameters->applySort($query, $sortable)
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    protected function noContent()
    {
        return response('', 204);
    }

    /**
     * Texto opcional de un atributo: recortado; vacío = null.
     */
    protected static function text($value): ?string
    {
        if ($value === null) {
            return null;
        }

        $value = trim((string) $value);

        return $value === '' ? null : $value;
    }
}
