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
    // En el vehículo, ida y regreso (docs/11 §11.63: Viajando y Recogido unificados)
    public const TRAVELLING = 'viajando';
    // Ida
    public const DROPPED = 'dejado';
    /** Nombre de la 4.2.0 de «Viajando» en el regreso: se acepta de los teléfonos viejos y se guarda como viajando. */
    public const LEGACY_PICKED_UP = 'recogido';
    // Ida (respecto a la primera parada) y regreso (respecto a su parada), docs/11 §11.61
    public const LEFT_BEHIND = 'botado';
    public const LATE = 'dormido';

    public const OUTBOUND_STATES = [self::ON_THE_WAY, self::AT_STOP, self::TRAVELLING, self::DROPPED, self::LEFT_BEHIND, self::LATE, self::NOT_GOING];
    public const RETURN_STATES = [self::ON_THE_WAY, self::AT_STOP, self::TRAVELLING, self::LEFT_BEHIND, self::LATE, self::NOT_GOING];

    /**
     * Estados finales (ya no cambian): Dejado en la ida y Viajando en el
     * regreso (bajan todos en la parada final). En la ida, Viajando es
     * semidefinitivo: solo pasa a Dejado.
     */
    public static function isFinal(string $state, bool $outbound): bool
    {
        return $state === self::DROPPED || (! $outbound && $state === self::TRAVELLING);
    }

    /** Estado recibido de un teléfono: «recogido» (4.2.0) es Viajando. */
    public static function normalize(?string $state): ?string
    {
        return $state === self::LEGACY_PICKED_UP ? self::TRAVELLING : $state;
    }

    protected $fillable = ['trip_id', 'user_id', 'stop_id', 'state', 'state_at', 'reported_at', 'children_count', 'child_ids', 'last_seen_at', 'gps_ok'];

    protected $casts = [
        'state_at' => 'datetime',
        'reported_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'gps_ok' => 'boolean',
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
