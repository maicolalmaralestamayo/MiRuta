<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\PasswordHistory;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\Hash;

/**
 * Política de contraseñas (docs/08-version-2.md §8.4; ajustes «Contraseñas» de docs/13). Todos los valores son
 * ajustes de la app. Las contraseñas se guardan con bcrypt; el historial
 * guarda solo hashes.
 */
class Passwords
{
    /** bcrypt solo usa los primeros 72 bytes. */
    const MAX_LENGTH = 72;

    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    /**
     * Comprueba la contraseña nueva. $context: usuario y nombres de la cuenta
     * (para no contenerlos). Lanza PASSWORD_POLICY con todos los motivos.
     */
    public function validate($password, array $context = [], ?User $user = null, string $pointer = '/data/attributes/password'): void
    {
        $problems = $this->problems($password, $context, $user);

        if ($problems !== []) {
            throw new JsonApiException(422, 'PASSWORD_POLICY', 'Contraseña no válida', implode(' ', $problems), ['pointer' => $pointer]);
        }
    }

    /**
     * @return string[] Motivos por los que no se acepta (vacío si se acepta)
     */
    public function problems($password, array $context = [], ?User $user = null): array
    {
        if (! is_string($password) || $password === '') {
            return ['Escriba una contraseña.'];
        }

        $problems = [];
        $min = $this->settings->int('longitud_contrasena');

        if (mb_strlen($password) < $min) {
            $problems[] = "Debe tener al menos {$min} caracteres.";
        }

        if (strlen($password) > self::MAX_LENGTH) {
            $problems[] = 'No puede tener más de '.self::MAX_LENGTH.' caracteres.';
        }

        $required = $this->settings->int('tipos_caracteres');

        if (self::classCount($password) < $required) {
            $problems[] = "Debe combinar al menos {$required} de estos tipos: mayúsculas, minúsculas, números y símbolos.";
        }

        if ($user && $this->wasUsedBefore($user, $password)) {
            $count = $this->settings->int('historial_contrasenas');
            $problems[] = "No puede ser igual a ninguna de sus {$count} contraseñas anteriores.";
        }

        return $problems;
    }

    /**
     * Contraseña propuesta (docs/11 §11.5 y §11.7): cumple la política, con
     * mayúsculas, minúsculas, números y un símbolo, sin caracteres que se
     * confundan (0/O, 1/l/I).
     */
    public function suggest(): string
    {
        $length = max(10, $this->settings->int('longitud_contrasena'));
        $sets = ['ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnopqrstuvwxyz', '23456789', '.-_*#'];
        $pick = function (string $set) {
            return $set[random_int(0, strlen($set) - 1)];
        };
        $characters = [$pick($sets[0]), $pick($sets[2]), $pick($sets[3])];

        while (count($characters) < $length - 1) {
            $characters[] = $pick(random_int(0, 2) === 0 ? $sets[0] : $sets[1]);
        }

        // La primera, una letra (más fácil de dictar); el resto, mezclado.
        $first = $pick($sets[0]);
        $rest = $characters;
        for ($i = count($rest) - 1; $i > 0; $i--) {
            $j = random_int(0, $i);
            $tmp = $rest[$i];
            $rest[$i] = $rest[$j];
            $rest[$j] = $tmp;
        }

        return $first.implode('', $rest);
    }

    /**
     * Guarda la contraseña nueva (ya validada) y la anterior en el historial.
     */
    public function set(User $user, string $password): void
    {
        if ($user->password) {
            PasswordHistory::create(['user_id' => $user->id, 'password_hash' => $user->password]);
        }

        $user->forceFill([
            'password' => Hash::make($password),
            'password_changed_at' => Carbon::now(),
            'must_change_password' => false,
        ])->save();

        $this->pruneHistory($user);
    }

    /**
     * La contraseña caducó (o hay que cambiarla tras recuperar el acceso).
     */
    public function mustChange(User $user): bool
    {
        return (bool) $user->must_change_password || $this->isExpired($user);
    }

    public function isExpired(User $user): bool
    {
        $expiresAt = $this->expiresAt($user);

        return $expiresAt !== null && $expiresAt->lte(Carbon::now());
    }

    public function expiresAt(User $user): ?Carbon
    {
        if (! $user->password_changed_at) {
            return null;
        }

        return Carbon::parse($user->password_changed_at)->addSeconds($this->settings->seconds('caducidad_contrasena'));
    }

    /**
     * Requisitos actuales, para que la app los muestre mientras se escribe.
     */
    public function policy(): array
    {
        return [
            'minLength' => $this->settings->int('longitud_contrasena'),
            'maxLength' => self::MAX_LENGTH,
            'requiredClasses' => $this->settings->int('tipos_caracteres'),
            'historyCount' => $this->settings->int('historial_contrasenas'),
            'expiryDays' => intdiv($this->settings->seconds('caducidad_contrasena'), 86400),
        ];
    }

    public static function classCount(string $password): int
    {
        return (int) (bool) preg_match('/\p{Lu}/u', $password)
            + (int) (bool) preg_match('/\p{Ll}/u', $password)
            + (int) (bool) preg_match('/\d/', $password)
            + (int) (bool) preg_match('/[^\p{L}\d]/u', $password);
    }


    private function wasUsedBefore(User $user, string $password): bool
    {
        $count = $this->settings->int('historial_contrasenas');

        if ($count <= 0) {
            return false;
        }

        if ($user->password && Hash::check($password, $user->password)) {
            return true;
        }

        // La actual cuenta como una de las N.
        $hashes = PasswordHistory::where('user_id', $user->id)->orderBy('id', 'desc')->limit(max(0, $count - 1))->pluck('password_hash');

        foreach ($hashes as $hash) {
            if (Hash::check($password, $hash)) {
                return true;
            }
        }

        return false;
    }

    private function pruneHistory(User $user): void
    {
        $keep = max(0, $this->settings->int('historial_contrasenas') - 1);
        $ids = PasswordHistory::where('user_id', $user->id)->orderBy('id', 'desc')->pluck('id')->slice($keep)->all();

        if ($ids !== []) {
            PasswordHistory::whereIn('id', $ids)->delete();
        }
    }

    private static function plain(string $text): string
    {
        $text = strtr(mb_strtolower($text, 'UTF-8'), ['á' => 'a', 'é' => 'e', 'í' => 'i', 'ó' => 'o', 'ú' => 'u', 'ü' => 'u', 'ñ' => 'n']);

        return preg_replace('/[^a-z0-9]/', '', $text);
    }
}
