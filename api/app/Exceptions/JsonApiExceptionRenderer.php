<?php

namespace App\Exceptions;

use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Database\QueryException;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Throwable;

/**
 * Toda la API responde los errores con el formato errors[] de JSON:API.
 */
class JsonApiExceptionRenderer
{
    public static function render(Throwable $exception)
    {
        if ($exception instanceof ValidationException) {
            return JsonApiResponse::make(['errors' => self::validationErrors($exception)], 422);
        }

        $error = self::toJsonApiException($exception);

        return JsonApiResponse::make(['errors' => [$error->toError()]], $error->getStatus());
    }

    private static function toJsonApiException(Throwable $exception): JsonApiException
    {
        if ($exception instanceof JsonApiException) {
            return $exception;
        }

        if ($exception instanceof ModelNotFoundException || $exception instanceof NotFoundHttpException) {
            return new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El recurso solicitado no existe.');
        }

        if ($exception instanceof MethodNotAllowedHttpException) {
            return new JsonApiException(405, 'METHOD_NOT_ALLOWED', 'Método no permitido', 'Este recurso no admite el método '.request()->getMethod().'.');
        }

        if ($exception instanceof AccessDeniedHttpException) {
            return new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tiene permiso para realizar esta acción.');
        }

        if ($exception instanceof QueryException
            && ((int) ($exception->errorInfo[1] ?? 0) === 1062 || stripos($exception->getMessage(), 'UNIQUE constraint failed') !== false)) {
            return JsonApiException::conflict('DUPLICATE', 'Ya existe un registro con esos datos.');
        }

        if ($exception instanceof HttpException) {
            return new JsonApiException($exception->getStatusCode(), 'HTTP_ERROR', 'Error', $exception->getMessage() ?: null);
        }

        report($exception);
        $detail = config('app.debug') ? get_class($exception).': '.$exception->getMessage() : null;

        return new JsonApiException(500, 'SERVER_ERROR', 'Error interno del servidor', $detail);
    }

    private static function validationErrors(ValidationException $exception): array
    {
        $errors = [];

        foreach ($exception->errors() as $field => $messages) {
            foreach ($messages as $message) {
                $errors[] = [
                    'status' => '422',
                    'code' => 'VALIDATION_ERROR',
                    'title' => 'Error de validación',
                    'detail' => $message,
                    'source' => ['pointer' => '/'.str_replace('.', '/', $field)],
                ];
            }
        }

        return $errors;
    }
}
