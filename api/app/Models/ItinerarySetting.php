<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Valor de un ajuste para un itinerario.
 */
class ItinerarySetting extends Model
{
    use SoftDeletes;

    protected $fillable = ['itinerary_id', 'setting_definition_id', 'value'];
}
