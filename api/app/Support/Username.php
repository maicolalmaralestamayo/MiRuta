<?php

namespace App\Support;

use Illuminate\Support\Facades\DB;

/**
 * Nombre de usuario para iniciar sesión (docs/02-procesos.md §2.1).
 *
 * - De 3 a 30 caracteres: letras minúsculas sin tilde, dígitos, punto y guion bajo.
 * - Empieza por una letra, así nunca se confunde con un carné (11 dígitos).
 * - Se guarda en minúsculas; al iniciar sesión da igual cómo se escriba.
 * - Único también entre los trabajadores inactivos.
 */
final class Username
{
    const PATTERN = '/^[a-z][a-z0-9._]{2,29}$/';

    const MAX_LENGTH = 30;

    public static function normalize($value): string
    {
        return is_string($value) ? mb_strtolower(trim($value), 'UTF-8') : '';
    }

    public static function isValid($value): bool
    {
        return is_string($value) && preg_match(self::PATTERN, self::normalize($value)) === 1;
    }

    /**
     * Propuesta a partir del nombre: primer nombre y primer apellido, sin
     * tildes ("María José Pérez Díaz" → "maria.perez"). Si ya existe, añade un número.
     */
    public static function suggest(string $firstName, string $lastName, ?int $ignoreWorkerId = null): string
    {
        $first = self::slug(self::firstWord($firstName));
        $last = self::slug(self::firstWord($lastName));
        $base = trim($first.'.'.$last, '.');

        if ($base === '' || ! ctype_alpha($base[0])) {
            $base = 'usuario'.$base;
        }

        $base = substr(str_pad($base, 3, '0'), 0, self::MAX_LENGTH - 3);
        $candidate = $base;

        for ($n = 2; self::taken($candidate, $ignoreWorkerId); $n++) {
            $candidate = $base.$n;
        }

        return $candidate;
    }

    public static function taken(string $username, ?int $ignoreWorkerId = null): bool
    {
        $query = DB::table('workers')->where('username', self::normalize($username));

        if ($ignoreWorkerId !== null) {
            $query->where('id', '<>', $ignoreWorkerId);
        }

        return $query->exists();
    }

    private static function firstWord(string $text): string
    {
        $words = preg_split('/\s+/u', trim($text));

        return $words ? $words[0] : '';
    }

    private static function slug(string $text): string
    {
        $text = strtr(mb_strtolower($text, 'UTF-8'), [
            'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n',
            'à' => 'a', 'è' => 'e', 'ì' => 'i', 'ò' => 'o', 'ù' => 'u', 'ç' => 'c',
        ]);

        return preg_replace('/[^a-z0-9]/', '', $text);
    }
}
