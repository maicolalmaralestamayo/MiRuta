<?php

namespace App\Support;

use Carbon\CarbonInterface;

/**
 * Fechas como las muestra la app (docs/11 §11.33): día de la semana abreviado
 * y año con 2 dígitos, separados por guiones, y horas de 24 h:
 * «sáb. 14-03-26 17:30».
 */
class SpanishDate
{
    public const WEEKDAYS = ['dom.', 'lun.', 'mar.', 'mié.', 'jue.', 'vie.', 'sáb.'];

    public static function date(?CarbonInterface $date): string
    {
        return $date ? self::WEEKDAYS[(int) $date->dayOfWeek].' '.$date->format('d-m-y') : '';
    }

    public static function dateTime(?CarbonInterface $date): string
    {
        return $date ? self::date($date).' '.$date->format('H:i') : '';
    }
}
