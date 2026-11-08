<?php

namespace App\Support;

/**
 * Valores con unidades de los ajustes (docs/11 §11.40 y §11.43).
 *
 * - Tiempos: seg, min, hor, dia, sem, mes (30 días), ano (365 días),
 *   combinables y cada unidad una sola vez: «12hor30min», «1ano6mes», «2sem3dia».
 * - Distancias: m y km, combinables: «100m», «1km200m».
 * - Velocidades: distancia/tiempo: «10km/hor», «200m/min» (si el tiempo no lleva
 *   número, vale 1: «10km/hor» = 10 km por hora).
 *
 * Solo números enteros, sin espacios (se quitan) y en minúsculas.
 */
final class Units
{
    /** Segundos de cada unidad de tiempo. */
    public const TIME = [
        'ano' => 31536000,
        'mes' => 2592000,
        'sem' => 604800,
        'dia' => 86400,
        'hor' => 3600,
        'min' => 60,
        'seg' => 1,
    ];

    /** Metros de cada unidad de distancia. */
    public const DISTANCE = [
        'km' => 1000,
        'm' => 1,
    ];

    /**
     * Segundos de un tiempo con unidades, o null si no es válido.
     */
    public static function seconds($value): ?int
    {
        return self::sum($value, self::TIME);
    }

    /**
     * Metros de una distancia con unidades, o null si no es válida.
     */
    public static function meters($value): ?int
    {
        return self::sum($value, self::DISTANCE);
    }

    /**
     * Metros por segundo de una velocidad («10km/hor»), o null si no es válida.
     */
    public static function metersPerSecond($value): ?float
    {
        if (! is_string($value)) {
            return null;
        }

        $parts = explode('/', self::clean($value));

        if (count($parts) !== 2) {
            return null;
        }

        $meters = self::meters($parts[0]);
        $time = isset(self::TIME[$parts[1]]) ? self::TIME[$parts[1]] : self::seconds($parts[1]);

        if ($meters === null || ! $time) {
            return null;
        }

        return $meters / $time;
    }

    /**
     * Texto con unidades a partir de segundos (la forma más corta): 3600 → «1hor».
     */
    public static function formatSeconds(int $seconds): string
    {
        return self::format($seconds, self::TIME, 'seg');
    }

    public static function formatMeters(int $meters): string
    {
        return self::format($meters, self::DISTANCE, 'm');
    }

    /**
     * Normaliza un valor (sin espacios y en minúsculas, «año» → «ano»).
     */
    public static function clean(string $value): string
    {
        return str_replace(['año', 'ñ'], ['ano', 'n'], mb_strtolower(preg_replace('/\s+/u', '', $value), 'UTF-8'));
    }

    private static function sum($value, array $units): ?int
    {
        if (is_int($value)) {
            return null;
        }

        if (! is_string($value)) {
            return null;
        }

        $value = self::clean($value);

        if ($value === '') {
            return null;
        }

        // Unidades más largas primero (para que «km» no se lea como «k» + «m»).
        $names = array_keys($units);
        usort($names, fn ($a, $b) => strlen($b) <=> strlen($a));
        $pattern = '/(\d+)('.implode('|', array_map('preg_quote', $names)).')/A';
        $offset = 0;
        $total = 0;
        $used = [];

        while ($offset < strlen($value)) {
            if (! preg_match($pattern, $value, $match, 0, $offset)) {
                return null;
            }

            if (isset($used[$match[2]]) || strlen($match[1]) > 9) {
                return null;
            }

            $used[$match[2]] = true;
            $total += (int) $match[1] * $units[$match[2]];
            $offset += strlen($match[0]);
        }

        return $total;
    }

    private static function format(int $amount, array $units, string $zeroUnit): string
    {
        if ($amount <= 0) {
            return '0'.$zeroUnit;
        }

        $text = '';

        foreach ($units as $name => $size) {
            if ($amount >= $size) {
                $text .= intdiv($amount, $size).$name;
                $amount %= $size;
            }
        }

        return $text;
    }
}
