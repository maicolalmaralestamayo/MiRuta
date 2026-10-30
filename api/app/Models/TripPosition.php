<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class TripPosition extends Model
{
    use SoftDeletes;

    protected $fillable = ['trip_leg_id', 'worker_id', 'latitude', 'longitude', 'accuracy_m', 'recorded_at'];

    protected $casts = [
        'latitude' => 'float',
        'longitude' => 'float',
        'accuracy_m' => 'float',
        'recorded_at' => 'datetime',
    ];

    public function tripLeg()
    {
        return $this->belongsTo(TripLeg::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }
}
