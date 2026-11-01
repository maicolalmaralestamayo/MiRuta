<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class TripStopPass extends Model
{
    use SoftDeletes;

    const STATUS_ARRIVED = 'arrived';
    const STATUS_STOPPED = 'stopped';
    const STATUS_NOT_STOPPED = 'not_stopped';
    const STATUS_SKIPPED = 'skipped';

    protected $fillable = ['trip_leg_id', 'stop_id', 'passed_at', 'left_at', 'min_speed_kmh', 'status'];

    protected $casts = [
        'passed_at' => 'datetime',
        'left_at' => 'datetime',
        'min_speed_kmh' => 'float',
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
