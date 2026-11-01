<?php

namespace App\Support;

use Carbon\CarbonInterface;

/**
 * Fechas como las muestra la app (docs/09 §8 y §14): día de la semana
 * abreviado y año con 2 dígitos, p. ej. "sáb. 31/10/26 13:51".
 */
class SpanishDate
{
    const WEEKDAYS = ['dom.', 'lun.', 'mar.', 'mié.', 'jue.', 'vie.', 'sáb.'];

    public static function date(?CarbonInterface $date): string
    {
        return $date ? self::WEEKDAYS[(int) $date->dayOfWeek].' '.$date->format('d/m/y') : '';
    }

    public static function dateTime(?CarbonInterface $date): string
    {
        return $date ? self::date($date).' '.$date->format('H:i') : '';
    }
}
