<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Hijo que subió con un trabajador. Cada niño cuenta una sola vez por
 * trayecto (único trip_leg_id + child_id). Al corregir se borra de verdad.
 */
class TripBoardingChild extends Model
{
    use SoftDeletes;

    protected $fillable = ['trip_boarding_id', 'trip_leg_id', 'child_id'];

    public function boarding()
    {
        return $this->belongsTo(TripBoarding::class, 'trip_boarding_id');
    }

    public function child()
    {
        return $this->belongsTo(Child::class)->withTrashed();
    }
}
