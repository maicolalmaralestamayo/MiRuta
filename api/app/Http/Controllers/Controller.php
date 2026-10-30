<?php

namespace App\Http\Controllers;

use App\JsonApi\JsonApiException;
use Illuminate\Http\Request;
use Laravel\Lumen\Routing\Controller as BaseController;

class Controller extends BaseController
{
    /**
     * Comprueba la estructura de un documento JSON:API de entrada y valida
     * sus atributos y relaciones.
     *
     * Las reglas se escriben con las claves de JSON:API, por ejemplo
     * "attributes.firstName" o "relationships.rank.data.id", y los errores
     * se devuelven con source.pointer = /data/attributes/firstName.
     *
     * @return array El objeto "data" validado.
     */
    protected function validateResource(Request $request, string $type, array $rules): array
    {
        $data = $request->json('data');

        if (! is_array($data)) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Petición incorrecta', 'El documento debe tener un objeto "data".', ['pointer' => '/data']);
        }

        if (! isset($data['type']) || $data['type'] !== $type) {
            throw JsonApiException::conflict('TYPE_MISMATCH', "El tipo del recurso debe ser \"{$type}\".", '/data/type');
        }

        $prefixed = [];

        foreach ($rules as $key => $keyRules) {
            $prefixed['data.'.$key] = $keyRules;
        }

        $this->validate($request, $prefixed);

        return $data;
    }
}
