<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Simulación de trabajadores (docs/11 §11.66): un viaje de prueba de un
 * itinerario con trabajadores simulados que envían sus estados y sus
 * observaciones del vehículo como los teléfonos reales. Una sola a la vez.
 */
class Simulation extends Model
{
    public const RUNNING = 'en_curso';
    public const FINISHED = 'terminada';

    public const VEHICLE_SIMULATED = 'simulado';
    public const VEHICLE_REAL = 'real';

    protected $fillable = [
        'itinerary_id', 'trip_id', 'created_by', 'direction', 'vehicle_mode', 'workers_count',
        'pct_normal', 'pct_late', 'pct_left_behind', 'pct_not_going', 'speed_factor', 'vehicle_speed_kmh',
        'seed', 'plan', 'status', 'started_at', 'last_tick_at', 'finished_at',
    ];

    protected $casts = [
        'itinerary_id' => 'integer',
        'trip_id' => 'integer',
        'created_by' => 'integer',
        'workers_count' => 'integer',
        'pct_normal' => 'integer',
        'pct_late' => 'integer',
        'pct_left_behind' => 'integer',
        'pct_not_going' => 'integer',
        'speed_factor' => 'integer',
        'vehicle_speed_kmh' => 'integer',
        'seed' => 'integer',
        'started_at' => 'datetime',
        'last_tick_at' => 'datetime',
        'finished_at' => 'datetime',
    ];

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function planData(): array
    {
        $plan = $this->plan ? json_decode($this->plan, true) : null;

        return is_array($plan) ? $plan : [];
    }

    public function isSimulatedVehicle(): bool
    {
        return $this->vehicle_mode === self::VEHICLE_SIMULATED;
    }
}
