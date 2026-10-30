<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Datos propios de un tipo de solicitud (subtipo de applications).
 */
class ItineraryApplication extends Model
{
    use SoftDeletes;

    protected $primaryKey = 'application_id';

    public $incrementing = false;

    protected $fillable = ['application_id', 'itinerary_id', 'stop_id'];

    public function application()
    {
        return $this->belongsTo(Application::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class)->withTrashed();
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class)->withTrashed();
    }
}
