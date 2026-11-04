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
    /** Quien tiene trips.complete sobre el viaje. */
    const ROLE_MANAGER = 'manager';
    const ROLE_ADMINISTRATOR = 'administrator';
    const ROLE_SYSTEM = 'system';

    protected $fillable = ['trip_id', 'user_id', 'role'];

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }
}
