<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Marca de "viaje realizado". Si el viaje deja de estar realizado, las marcas
 * se conservan con borrado lógico.
 */
class TripCompletion extends Model
{
    use SoftDeletes;

    const ROLE_DRIVER = 'driver';
    const ROLE_ITINERARY_CHIEF = 'itinerary_chief';
    const ROLE_TRANSPORT_CHIEF = 'transport_chief';
    const ROLE_ADMINISTRATOR = 'administrator';
    const ROLE_SYSTEM = 'system';

    protected $fillable = ['trip_id', 'worker_id', 'role'];

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }
}
