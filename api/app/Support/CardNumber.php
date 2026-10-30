<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Crypt;
use RuntimeException;

/**
 * Carné de identidad de 11 dígitos (docs/07-algoritmos.md §7.1).
 *
 * - Dígitos 1-6: fecha de nacimiento AAMMDD.
 * - Dígito 7: siglo (9 → 1800, 0-5 → 1900, 6-8 → 2000).
 * - Penúltimo dígito: sexo (par → M, impar → F).
 */
final class CardNumber
{
    /** @var string */
    private $value;

    /** @var CarbonImmutable */
    private $birthDate;

    private function __construct(string $value, CarbonImmutable $birthDate)
    {
        $this->value = $value;
        $this->birthDate = $birthDate;
    }

    /**
     * Devuelve el carné si es válido, o null si no lo es.
     */
    public static function tryParse($value): ?self
    {
        if (! is_string($value) || ! preg_match('/^\d{11}$/', $value)) {
            return null;
        }

        $year = self::century((int) $value[6]) + (int) substr($value, 0, 2);
        $month = (int) substr($value, 2, 2);
        $day = (int) substr($value, 4, 2);

        if (! checkdate($month, $day, $year)) {
            return null;
        }

        $birthDate = CarbonImmutable::create($year, $month, $day, 0, 0, 0);

        if ($birthDate->isAfter(CarbonImmutable::today())) {
            return null;
        }

        return new self($value, $birthDate);
    }

    public static function isValid($value): bool
    {
        return self::tryParse($value) !== null;
    }

    /**
     * Huella HMAC-SHA256 para buscar el carné sin descifrarlo.
     */
    public static function hashOf(string $value): string
    {
        $key = config('mitransporte.card_hash_key');

        if (! $key) {
            throw new RuntimeException('Falta CARD_HASH_KEY en la configuración.');
        }

        return hash_hmac('sha256', $value, $key);
    }

    public function value(): string
    {
        return $this->value;
    }

    public function birthDate(): CarbonImmutable
    {
        return $this->birthDate;
    }

    public function sex(): string
    {
        return ((int) $this->value[9]) % 2 === 0 ? 'M' : 'F';
    }

    public function hash(): string
    {
        return self::hashOf($this->value);
    }

    public function encrypt(): string
    {
        return Crypt::encryptString($this->value);
    }

    private static function century(int $digit): int
    {
        if ($digit === 9) {
            return 1800;
        }

        return $digit <= 5 ? 1900 : 2000;
    }
}
