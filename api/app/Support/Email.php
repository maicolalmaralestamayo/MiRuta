<?php

namespace App\Support;

use App\JsonApi\JsonApiException;

/**
 * Correo electrónico de la persona (docs/11 §11.67): sustituye al carné de
 * identidad. Se guarda en minúsculas y es único en toda la base de datos.
 */
final class Email
{
    const MAX = 150;

    public static function normalize($value): string
    {
        return is_string($value) ? mb_strtolower(trim($value)) : '';
    }

    /**
     * Motivo por el que no es válido, o null.
     */
    public static function error($value): ?string
    {
        $email = self::normalize($value);

        if ($email === '') {
            return 'Escriba el correo electrónico.';
        }

        if (mb_strlen($email) > self::MAX || ! filter_var($email, FILTER_VALIDATE_EMAIL) || ! preg_match('/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/u', $email)) {
            return 'El correo electrónico no es válido (p. ej. nombre@correo.cu).';
        }

        return null;
    }

    public static function isValid($value): bool
    {
        return self::error($value) === null;
    }

    /**
     * Comprueba el correo y lo devuelve normalizado (422 EMAIL_INVALID).
     */
    public static function validated($value, string $pointer = '/data/attributes/email'): string
    {
        if ($error = self::error($value)) {
            throw new JsonApiException(422, 'EMAIL_INVALID', 'Correo no válido', $error, ['pointer' => $pointer]);
        }

        return self::normalize($value);
    }
}
