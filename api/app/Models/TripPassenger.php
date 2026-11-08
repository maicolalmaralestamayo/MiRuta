<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Estado de un trabajador en un viaje (docs/11 §11.43). Lo calcula su teléfono
 * y envía solo los cambios.
 */
class TripPassenger extends Model
{
    // Ida y regreso
    public const ON_THE_WAY = 'de_camino';
    public const AT_STOP = 'en_parada';
    public const NOT_GOING = 'no_voy';
    // Ida
    public const TRAVELLING = 'viajando';
    public const DROPPED = 'dejado';
    // Regreso
    public const PICKED_UP = 'recogido';
    public const LEFT_BEHIND = 'botado';
    public const LATE = 'dormido';

    public const OUTBOUND_STATES = [self::ON_THE_WAY, self::AT_STOP, self::TRAVELLING, self::DROPPED, self::NOT_GOING];
    public const RETURN_STATES = [self::ON_THE_WAY, self::AT_STOP, self::PICKED_UP, self::LEFT_BEHIND, self::LATE, self::NOT_GOING];

    /** Estados finales: ya no cambian. */
    public const FINAL_STATES = [self::DROPPED, self::PICKED_UP];

    protected $fillable = ['trip_id', 'user_id', 'stop_id', 'state', 'state_at', 'reported_at', 'children_count', 'child_ids', 'last_seen_at'];

    protected $casts = [
        'state_at' => 'datetime',
        'reported_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'children_count' => 'integer',
        'trip_id' => 'integer',
        'user_id' => 'integer',
        'stop_id' => 'integer',
    ];

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }

    /** @return int[] */
    public function childIds(): array
    {
        return $this->child_ids ? array_map('intval', explode(',', $this->child_ids)) : [];
    }
}
