<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Viaje: un itinerario con un vehículo y un chofer, con salida y regreso.
 */
class Trip extends Model
{
    use SoftDeletes;

    const STATUS_UNCONFIRMED = 'unconfirmed';
    const STATUS_CONFIRMED = 'confirmed';
    const STATUS_COMPLETED = 'completed';
    const STATUS_CANCELLED = 'cancelled';

    const STATUSES = [self::STATUS_UNCONFIRMED, self::STATUS_CONFIRMED, self::STATUS_COMPLETED, self::STATUS_CANCELLED];

    protected $fillable = ['itinerary_id', 'vehicle_id', 'driver_id', 'departs_at', 'returns_at', 'status', 'created_by'];

    protected $casts = [
        'departs_at' => 'datetime',
        'returns_at' => 'datetime',
    ];

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class)->withTrashed();
    }

    public function vehicle()
    {
        return $this->belongsTo(Vehicle::class)->withTrashed();
    }

    /**
     * El chofer puede haberse dado de baja (viaje pendiente de reasignar).
     */
    public function driver()
    {
        return $this->belongsTo(Driver::class)->withTrashed();
    }

    public function legs()
    {
        return $this->hasMany(TripLeg::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by')->withTrashed();
    }

    public function completions()
    {
        return $this->hasMany(TripCompletion::class);
    }

    public function isPending(): bool
    {
        return in_array($this->status, [self::STATUS_UNCONFIRMED, self::STATUS_CONFIRMED], true);
    }
}
