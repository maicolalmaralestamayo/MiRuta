<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Valor de un ajuste para una parada de un itinerario.
 */
class ItineraryStopSetting extends Model
{
    use SoftDeletes;

    protected $fillable = ['itinerary_stop_id', 'setting_definition_id', 'value'];
}
