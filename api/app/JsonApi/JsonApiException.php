<?php

namespace App\JsonApi;

use RuntimeException;

/**
 * Error que se devuelve con el formato errors[] de JSON:API.
 */
class JsonApiException extends RuntimeException
{
    /** @var int */
    private $status;

    /** @var string */
    private $errorCode;

    /** @var string */
    private $title;

    /** @var string|null */
    private $detail;

    /** @var array */
    private $source;

    /** @var array */
    private $meta;

    public function __construct(int $status, string $errorCode, string $title, ?string $detail = null, array $source = [], array $meta = [])
    {
        parent::__construct($detail ?: $title);

        $this->status = $status;
        $this->errorCode = $errorCode;
        $this->title = $title;
        $this->detail = $detail;
        $this->source = $source;
        $this->meta = $meta;
    }

    public static function badRequest(string $detail, ?string $parameter = null): self
    {
        return new self(400, 'BAD_REQUEST', 'Petición incorrecta', $detail, $parameter ? ['parameter' => $parameter] : []);
    }

    public static function conflict(string $errorCode, string $detail, ?string $pointer = null, array $meta = []): self
    {
        return new self(409, $errorCode, 'Conflicto', $detail, $pointer ? ['pointer' => $pointer] : [], $meta);
    }

    public function getStatus(): int
    {
        return $this->status;
    }

    public function toError(): array
    {
        return array_filter([
            'status' => (string) $this->status,
            'code' => $this->errorCode,
            'title' => $this->title,
            'detail' => $this->detail,
            'source' => $this->source ?: null,
            'meta' => $this->meta ?: null,
        ], function ($value) {
            return $value !== null;
        });
    }
}
