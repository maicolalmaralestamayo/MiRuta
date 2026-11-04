<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class Vehicle extends Model
{
    use SoftDeletes;

    protected $fillable = ['entity_id', 'vehicle_type_id', 'plate', 'seats', 'standing_capacity', 'driver_id'];

    protected $casts = [
        'seats' => 'integer',
        'standing_capacity' => 'integer',
    ];

    public function vehicleType()
    {
        return $this->belongsTo(VehicleType::class);
    }

    /**
     * Chofer habitual: una pertenencia (worker) con tracking.drive.
     */
    public function driver()
    {
        return $this->belongsTo(Worker::class, 'driver_id')->withTrashed();
    }

    /**
     * Capacidad total = asientos + capacidad de pie. Se calcula, no se guarda.
     */
    public function totalCapacity(): int
    {
        return $this->seats + $this->standing_capacity;
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }

}
