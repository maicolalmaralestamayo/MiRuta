<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Driver extends Model
{
    use SoftDeletes;

    protected $fillable = ['worker_id'];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    /**
     * Vehículos en los que es el chofer habitual.
     */
    public function vehicles()
    {
        return $this->hasMany(Vehicle::class);
    }
}
