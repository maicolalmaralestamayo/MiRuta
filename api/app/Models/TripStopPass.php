<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class TripStopPass extends Model
{
    use SoftDeletes;

    protected $fillable = ['trip_leg_id', 'stop_id', 'passed_at'];

    protected $casts = [
        'passed_at' => 'datetime',
    ];

    public function tripLeg()
    {
        return $this->belongsTo(TripLeg::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class)->withTrashed();
    }
}
