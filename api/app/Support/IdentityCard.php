<?php

namespace App\Support;

use App\JsonApi\JsonApiException;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Crypt;

/**
 * Carné de identidad (docs/11 §11.2): 11 dígitos.
 *
 * - Los 6 primeros (AAMMDD) son la fecha de nacimiento.
 * - El 7.º da el siglo: 9 → 1800; 0–5 → 1900; 6–8 → 2000.
 * - El penúltimo da el sexo: par → masculino; impar → femenino.
 *
 * Se guarda cifrado, con una huella (HMAC) para buscarlo y comprobar que no
 * se repite.
 */
final class IdentityCard
{
    const LENGTH = 11;

    public static function normalize($value): string
    {
        return is_string($value) || is_int($value) ? preg_replace('/\s+/', '', (string) $value) : '';
    }

    /**
     * Motivo por el que no es válido, o null.
     */
    public static function error($value): ?string
    {
        $card = self::normalize($value);

        if (! preg_match('/^\d{11}$/', $card)) {
            return 'El carné de identidad debe tener 11 dígitos.';
        }

        $date = self::birthDateOrNull($card);

        if (! $date) {
            return 'Los 6 primeros dígitos del carné de identidad no son una fecha válida.';
        }

        if ($date->isFuture()) {
            return 'La fecha de nacimiento del carné de identidad no puede ser futura.';
        }

        return null;
    }

    public static function isValid($value): bool
    {
        return self::error($value) === null;
    }

    /**
     * Comprueba el carné y lo devuelve normalizado (422 IDENTITY_CARD_INVALID).
     */
    public static function validated($value, string $pointer = '/data/attributes/identityCard'): string
    {
        if ($error = self::error($value)) {
            throw new JsonApiException(422, 'IDENTITY_CARD_INVALID', 'Carné no válido', $error, ['pointer' => $pointer]);
        }

        return self::normalize($value);
    }

    public static function birthDate(string $card): CarbonImmutable
    {
        return self::birthDateOrNull(self::normalize($card));
    }

    /**
     * 'M' o 'F'.
     */
    public static function sex(string $card): string
    {
        $card = self::normalize($card);

        return ((int) $card[9]) % 2 === 0 ? 'M' : 'F';
    }

    public static function hash(string $card): string
    {
        return hash_hmac('sha256', 'identity-card:'.self::normalize($card), (string) config('app.key'));
    }

    public static function encrypt(string $card): string
    {
        return Crypt::encryptString(self::normalize($card));
    }

    public static function decrypt(?string $encrypted): ?string
    {
        return $encrypted ? Crypt::decryptString($encrypted) : null;
    }

    /**
     * Columnas a guardar: cifrado, huella, sexo y fecha de nacimiento.
     */
    public static function columns(string $card): array
    {
        return [
            'identity_card_encrypted' => self::encrypt($card),
            'identity_card_hash' => self::hash($card),
            'sex' => self::sex($card),
            'birth_date' => self::birthDate($card)->toDateString(),
        ];
    }

    /**
     * Construye un carné válido (pruebas y datos de ejemplo).
     */
    public static function make(string $birthDate, string $sex, int $serial = 1): string
    {
        $date = CarbonImmutable::parse($birthDate);
        $centuryDigit = $date->year < 1900 ? 9 : ($date->year < 2000 ? $serial % 6 : 6 + $serial % 3);
        $sexDigit = (($serial % 5) * 2) + ($sex === 'F' ? 1 : 0);
        $middle = str_pad((string) ($serial % 100), 2, '0', STR_PAD_LEFT);

        return $date->format('ymd').$centuryDigit.$middle.$sexDigit.($serial % 10);
    }

    private static function birthDateOrNull(string $card): ?CarbonImmutable
    {
        if (! preg_match('/^(\d{2})(\d{2})(\d{2})(\d)/', $card, $match)) {
            return null;
        }

        $century = (int) $match[4];
        $base = $century === 9 ? 1800 : ($century <= 5 ? 1900 : 2000);
        $year = $base + (int) $match[1];
        $month = (int) $match[2];
        $day = (int) $match[3];

        if (! checkdate($month, $day, $year)) {
            return null;
        }

        return CarbonImmutable::create($year, $month, $day)->startOfDay();
    }
}
