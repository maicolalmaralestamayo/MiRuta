<?php

namespace App\JsonApi;

use Illuminate\Http\JsonResponse;

class JsonApiResponse
{
    public static function make(array $document, int $status = 200, array $headers = []): JsonResponse
    {
        return new JsonResponse(
            $document,
            $status,
            array_merge(['Content-Type' => MediaType::JSON_API], $headers),
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES
        );
    }
}
