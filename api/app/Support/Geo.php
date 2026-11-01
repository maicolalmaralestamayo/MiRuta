<?php

namespace App\Support;

/**
 * Cálculos geográficos.
 */
final class Geo
{
    const EARTH_RADIUS_M = 6371000;

    /**
     * Distancia en metros entre dos puntos (fórmula del haversine).
     */
    public static function distance(float $lat1, float $lng1, float $lat2, float $lng2): float
    {
        $dLat = deg2rad($lat2 - $lat1);
        $dLng = deg2rad($lng2 - $lng1);
        $a = sin($dLat / 2) ** 2 + cos(deg2rad($lat1)) * cos(deg2rad($lat2)) * sin($dLng / 2) ** 2;

        return 2 * self::EARTH_RADIUS_M * asin(min(1, sqrt($a)));
    }

    /**
     * Distancia en metros de un punto a una línea quebrada [[lat, lng], …]
     * (proyección equirectangular local: suficiente a escala de ciudad).
     */
    public static function distanceToPolyline(float $lat, float $lng, array $line): float
    {
        if (! $line) {
            return INF;
        }

        if (count($line) === 1) {
            return self::distance($lat, $lng, $line[0][0], $line[0][1]);
        }

        $cos = cos(deg2rad($lat));
        $toXY = function (array $point) use ($lat, $lng, $cos) {
            return [deg2rad($point[1] - $lng) * $cos * self::EARTH_RADIUS_M, deg2rad($point[0] - $lat) * self::EARTH_RADIUS_M];
        };
        $best = INF;
        $previous = $toXY($line[0]);

        for ($i = 1, $n = count($line); $i < $n; $i++) {
            $current = $toXY($line[$i]);
            $dx = $current[0] - $previous[0];
            $dy = $current[1] - $previous[1];
            $lengthSquared = $dx * $dx + $dy * $dy;
            $t = $lengthSquared > 0 ? max(0, min(1, -($previous[0] * $dx + $previous[1] * $dy) / $lengthSquared)) : 0;
            $x = $previous[0] + $t * $dx;
            $y = $previous[1] + $t * $dy;
            $best = min($best, sqrt($x * $x + $y * $y));
            $previous = $current;
        }

        return $best;
    }

    /**
     * Mediana de una lista de números.
     */
    public static function median(array $values): float
    {
        sort($values);
        $count = count($values);
        $middle = intdiv($count, 2);

        return $count % 2 ? (float) $values[$middle] : ($values[$middle - 1] + $values[$middle]) / 2;
    }
}
