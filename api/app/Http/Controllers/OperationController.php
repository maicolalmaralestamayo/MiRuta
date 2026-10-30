<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\MediaType;
use App\Models\Trip;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\ValidationException;

/**
 * Extensión Atomic Operations de JSON:API: varias operaciones que se aplican
 * todas o ninguna. Se usa para crear viajes por rango de fechas, confirmar o
 * desconfirmar en masa y enviar posiciones acumuladas.
 */
class OperationController extends Controller
{
    const EXTENSION = 'https://jsonapi.org/ext/atomic';

    const MAX_OPERATIONS = 500;

    public function store(Request $request, TripController $trips)
    {
        if (strpos((string) $request->header('Content-Type'), self::EXTENSION) === false) {
            throw new JsonApiException(415, 'UNSUPPORTED_MEDIA_TYPE', 'Tipo de contenido no admitido',
                'Las operaciones atómicas requieren Content-Type: '.MediaType::JSON_API.'; ext="'.self::EXTENSION.'".');
        }

        $operations = $request->json('atomic:operations');

        if (! is_array($operations) || ! $operations || count($operations) > self::MAX_OPERATIONS) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Petición incorrecta',
                'El documento debe tener entre 1 y '.self::MAX_OPERATIONS.' operaciones en "atomic:operations".', ['pointer' => '/atomic:operations']);
        }

        $document = new Document($request);
        $errors = [];

        DB::beginTransaction();

        try {
            $results = [];

            foreach ($operations as $index => $operation) {
                try {
                    $model = $this->execute($operation, $index, $request, $trips);
                    $results[] = $model ? ['data' => $document->resourceObjectFor($model)] : new \stdClass();
                } catch (JsonApiException $exception) {
                    // El solapamiento se acumula para indicar todos los días que chocan.
                    $error = $exception->toError();

                    if ($error['code'] !== 'TRIP_OVERLAP') {
                        throw $exception;
                    }

                    $error['source'] = ['pointer' => "/atomic:operations/{$index}"];
                    $errors[] = $error;
                }
            }

            if ($errors) {
                DB::rollBack();

                return JsonApiResponse::make(['errors' => $errors], 409);
            }

            DB::commit();
        } catch (\Throwable $exception) {
            DB::rollBack();
            throw $exception;
        }

        return JsonApiResponse::make(['atomic:results' => $results], 200, [
            'Content-Type' => MediaType::JSON_API.'; ext="'.self::EXTENSION.'"',
        ]);
    }

    private function execute($operation, int $index, Request $request, TripController $trips)
    {
        $pointer = "/atomic:operations/{$index}";

        if (! is_array($operation) || ! isset($operation['op'], $operation['data']['type'])) {
            throw new JsonApiException(400, 'BAD_REQUEST', 'Operación incorrecta', 'Cada operación necesita "op" y "data.type".', ['pointer' => $pointer]);
        }

        $data = $operation['data'];
        $key = $operation['op'].':'.$data['type'];

        switch ($key) {
            case 'add:trips':
                $trips->authorizeManagement($request);
                $this->validateOperation($data, $trips->rules(true), $pointer);

                return $trips->create($data, $request);

            case 'update:trips':
                $trips->authorizeManagement($request);
                $id = isset($data['id']) ? $data['id'] : (isset($operation['ref']['id']) ? $operation['ref']['id'] : null);
                $this->validateOperation($data, $trips->rules(false), $pointer);

                return $trips->modify(Trip::findOrFail($id), $data, $request);

            default:
                if ($handler = $this->extraHandler($key)) {
                    return $handler($data, $request, $pointer);
                }

                throw new JsonApiException(400, 'OPERATION_NOT_SUPPORTED', 'Operación no admitida',
                    "La operación \"{$operation['op']}\" sobre \"{$data['type']}\" no está admitida.", ['pointer' => $pointer.'/op']);
        }
    }

    /**
     * Operaciones de otros recursos (registradas en config/jsonapi.php).
     */
    private function extraHandler(string $key): ?callable
    {
        $handlers = config('jsonapi.operations', []);

        if (! isset($handlers[$key])) {
            return null;
        }

        list($class, $method) = $handlers[$key];

        return [app($class), $method];
    }

    private function validateOperation(array $data, array $rules, string $pointer): void
    {
        $prefixed = [];

        foreach ($rules as $key => $value) {
            $prefixed['data.'.$key] = $value;
        }

        $validator = Validator::make(['data' => $data], $prefixed);

        if ($validator->fails()) {
            $first = $validator->errors()->keys()[0];
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Error de validación', $validator->errors()->first(),
                ['pointer' => $pointer.'/'.str_replace('.', '/', $first)]);
        }
    }
}
