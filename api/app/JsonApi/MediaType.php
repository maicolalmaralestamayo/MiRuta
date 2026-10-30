<?php

namespace App\JsonApi;

/**
 * Reglas de negociación del tipo de contenido de JSON:API 1.1.
 */
class MediaType
{
    const JSON_API = 'application/vnd.api+json';

    /** Parámetros que JSON:API permite junto al tipo de contenido. */
    const ALLOWED_PARAMETERS = ['ext', 'profile'];

    /**
     * Indica si una cabecera Content-Type es el tipo JSON:API con, como mucho,
     * los parámetros permitidos.
     */
    public static function isValidContentType(?string $header): bool
    {
        if ($header === null || $header === '') {
            return false;
        }

        list($type, $parameters) = self::parse($header);

        return $type === self::JSON_API && self::hasOnlyAllowedParameters($parameters);
    }

    /**
     * Indica si una cabecera Accept admite JSON:API. Según la especificación,
     * se rechaza (406) cuando todas las apariciones del tipo JSON:API llevan
     * parámetros no permitidos.
     */
    public static function isAcceptable(?string $header): bool
    {
        if ($header === null || $header === '') {
            return true;
        }

        $jsonApiEntries = 0;

        foreach (explode(',', $header) as $entry) {
            list($type, $parameters) = self::parse($entry);

            if ($type !== self::JSON_API) {
                continue;
            }

            $jsonApiEntries++;
            unset($parameters['q']);

            if (self::hasOnlyAllowedParameters($parameters)) {
                return true;
            }
        }

        return $jsonApiEntries === 0;
    }

    /**
     * @return array [tipo, [parámetro => valor]]
     */
    private static function parse(string $value): array
    {
        $parts = array_map('trim', explode(';', $value));
        $type = strtolower(array_shift($parts));
        $parameters = [];

        foreach ($parts as $part) {
            if ($part === '') {
                continue;
            }

            $pair = array_map('trim', explode('=', $part, 2));
            $parameters[strtolower($pair[0])] = isset($pair[1]) ? trim($pair[1], '"') : '';
        }

        return [$type, $parameters];
    }

    private static function hasOnlyAllowedParameters(array $parameters): bool
    {
        return count(array_diff(array_keys($parameters), self::ALLOWED_PARAMETERS)) === 0;
    }
}
