<?php

namespace App\Exceptions;

use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Database\QueryException;
use Illuminate\Validation\ValidationException;
use Laravel\Lumen\Exceptions\Handler as ExceptionHandler;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Throwable;

class Handler extends ExceptionHandler
{
    /**
     * Códigos de error JSON:API para las reglas de validación propias.
     * Las demás reglas producen VALIDATION_ERROR.
     */
    const RULE_CODES = [];

    /**
     * A list of the exception types that should not be reported.
     *
     * @var array
     */
    protected $dontReport = [
        AuthorizationException::class,
        HttpException::class,
        JsonApiException::class,
        ModelNotFoundException::class,
        ValidationException::class,
    ];

    /**
     * Report or log an exception.
     *
     * @param  \Throwable  $exception
     * @return void
     *
     * @throws \Exception
     */
    public function report(Throwable $exception)
    {
        parent::report($exception);
    }

    /**
     * Toda la API responde los errores con el formato errors[] de JSON:API.
     *
     * @param  \Illuminate\Http\Request  $request
     * @param  \Throwable  $exception
     * @return \Illuminate\Http\JsonResponse
     */
    public function render($request, Throwable $exception)
    {
        if ($exception instanceof ValidationException) {
            return JsonApiResponse::make(['errors' => $this->validationErrors($exception)], 422);
        }

        $error = $this->toJsonApiException($exception);

        return JsonApiResponse::make(['errors' => [$error->toError()]], $error->getStatus());
    }

    private function toJsonApiException(Throwable $exception): JsonApiException
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

        if ($exception instanceof QueryException && isset($exception->errorInfo[1]) && (int) $exception->errorInfo[1] === 1062) {
            return JsonApiException::conflict('DUPLICATE', 'Ya existe un registro con esos datos.');
        }

        if ($exception instanceof AuthorizationException) {
            return new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'No tienes permiso para realizar esta acción.');
        }

        if ($exception instanceof HttpException) {
            return new JsonApiException($exception->getStatusCode(), 'HTTP_ERROR', 'Error', $exception->getMessage() ?: null);
        }

        $detail = config('app.debug') ? get_class($exception).': '.$exception->getMessage() : null;

        return new JsonApiException(500, 'SERVER_ERROR', 'Error interno del servidor', $detail);
    }

    private function validationErrors(ValidationException $exception): array
    {
        $failed = $exception->validator->failed();
        $errors = [];

        foreach ($exception->errors() as $field => $messages) {
            $rules = isset($failed[$field]) ? array_keys($failed[$field]) : [];
            $code = isset($rules[0], self::RULE_CODES[$rules[0]]) ? self::RULE_CODES[$rules[0]] : 'VALIDATION_ERROR';

            foreach ($messages as $message) {
                $errors[] = [
                    'status' => '422',
                    'code' => $code,
                    'title' => 'Error de validación',
                    'detail' => $message,
                    'source' => ['pointer' => '/'.str_replace('.', '/', $field)],
                ];
            }
        }

        return $errors;
    }
}
