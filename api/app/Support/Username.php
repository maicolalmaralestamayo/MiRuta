<?php

namespace App\Support;

use App\Models\ReleasedUsername;
use App\Services\Settings;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Nombre de usuario (docs/08-version-2.md §8.3). Lo elige el propio usuario.
 *
 * - De 4 a 20 caracteres: letras sin tilde, números, punto y guion bajo.
 * - Empieza por letra y no termina en signo; sin dos signos seguidos.
 * - Al menos 3 letras; ningún carácter repetido más de 3 veces seguidas.
 * - Sin palabras reservadas ni palabras no permitidas (nomenclador).
 * - En minúsculas, único en toda la app; el que alguien deja de usar queda
 *   bloqueado para los demás durante username_reuse_block_days.
 */
final class Username
{
    const MIN_LENGTH = 4;
    const MAX_LENGTH = 20;

    /** Nadie puede hacerse pasar por la app o por su equipo. */
    const RESERVED = [
        'admin', 'administrador', 'administrator', 'soporte', 'support', 'sistema', 'system',
        'mitransporte', 'miruta', 'root', 'moderador', 'moderator', 'desarrollador', 'developer', 'oficial',
    ];

    /** Números que se usan para camuflar letras. */
    const LEET = ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't', '8' => 'b', '9' => 'g'];

    public static function normalize($value): string
    {
        return is_string($value) ? mb_strtolower(trim($value), 'UTF-8') : '';
    }

    /**
     * Cumple el formato (sin consultar la base de datos).
     */
    public static function looksValid($value): bool
    {
        return self::formatError($value) === null;
    }

    /**
     * Motivo por el que el formato no es válido, o null.
     */
    public static function formatError($value): ?string
    {
        $username = self::normalize($value);
        $length = strlen($username);

        if ($length < self::MIN_LENGTH || $length > self::MAX_LENGTH) {
            return 'El usuario debe tener de '.self::MIN_LENGTH.' a '.self::MAX_LENGTH.' caracteres.';
        }

        if (! preg_match('/^[a-z0-9._]+$/', $username)) {
            return 'El usuario solo puede tener letras sin tilde, números, punto y guion bajo.';
        }

        if (! preg_match('/^[a-z]/', $username)) {
            return 'El usuario tiene que empezar por una letra.';
        }

        if (preg_match('/[._]$/', $username)) {
            return 'El usuario no puede terminar en punto ni en guion bajo.';
        }

        if (preg_match('/[._]{2}/', $username)) {
            return 'El usuario no puede tener dos signos seguidos.';
        }

        if (preg_match_all('/[a-z]/', $username) < 3) {
            return 'El usuario tiene que tener al menos 3 letras.';
        }

        if (preg_match('/(.)\1{3}/', $username)) {
            return 'El usuario no puede repetir un carácter más de 3 veces seguidas.';
        }

        return null;
    }

    /**
     * Motivo por el que no se puede usar ese usuario (formato, palabras,
     * reservadas o no permitidas), o null. Que esté libre se comprueba con taken().
     */
    public static function unavailableReason($value): ?string
    {
        if ($error = self::formatError($value)) {
            return $error;
        }

        $username = self::normalize($value);

        if (self::containsReservedWord($username)) {
            return 'El usuario no puede contener palabras reservadas de la app.';
        }

        return null;
    }

    /**
     * Ya lo usa otra cuenta (activa o no) o lo dejó hace poco otra persona.
     */
    public static function taken(string $username, ?int $userId = null): bool
    {
        $username = self::normalize($username);
        $query = DB::table('users')->where('username', $username);

        if ($userId !== null) {
            $query->where('id', '<>', $userId);
        }

        if ($query->exists()) {
            return true;
        }

        $days = app(Settings::class)->int('username_reuse_block_days');
        $released = ReleasedUsername::where('username', $username)
            ->where('released_at', '>', Carbon::now()->subDays($days));

        if ($userId !== null) {
            // Quien lo dejó puede recuperarlo.
            $released->where('user_id', '<>', $userId);
        }

        return $days > 0 && $released->exists();
    }

    public static function containsReservedWord(string $username): bool
    {
        $plain = self::plain($username);

        foreach (self::RESERVED as $word) {
            if (strpos($plain, $word) !== false) {
                return true;
            }
        }

        return false;
    }


    /**
     * Sin tildes, sin signos y con los números camuflados convertidos en letras.
     */
    private static function plain(string $text): string
    {
        return preg_replace('/[^a-z]/', '', self::deLeet($text));
    }

    private static function deLeet(string $text): string
    {
        $text = strtr(mb_strtolower($text, 'UTF-8'), [
            'á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n',
        ]);

        return strtr($text, self::LEET);
    }
}
