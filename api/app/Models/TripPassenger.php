<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Estado de un trabajador en un viaje (docs/11 §11.43). Lo calcula su teléfono
 * y envía solo los cambios, con la hora de captura; stop_id es la parada
 * detectada por cercanía (docs/11 §11.65).
 */
class TripPassenger extends Model
{
    // Estados, iguales en la ida y en el regreso (docs/11 §11.65).
    public const ON_THE_WAY = 'de_camino';
    public const AT_STOP = 'en_parada';
    public const TRAVELLING = 'viajando';
    public const DROPPED = 'dejado';
    /** Estaba En la parada, el vehículo pasó por ella y no subió (antes «botado»). */
    public const LEFT_BEHIND = 'no_recogido';
    /** Estaba De camino y el vehículo pasó por su parada antes de que llegara (antes «dormido»). */
    public const LATE = 'retrasado';
    public const NOT_GOING = 'no_voy';

    /** Nombres de la 4.2.0 y de la 4.3.0 que aún envían los teléfonos viejos. */
    public const LEGACY_PICKED_UP = 'recogido';
    public const LEGACY_LEFT_BEHIND = 'botado';
    public const LEGACY_LATE = 'dormido';

    public const STATES = [self::ON_THE_WAY, self::AT_STOP, self::TRAVELLING, self::DROPPED, self::LEFT_BEHIND, self::LATE, self::NOT_GOING];

    /** Estados en que el trabajador está en una parada detectada (cantidades de la línea). */
    public const STOP_STATES = [self::ON_THE_WAY, self::AT_STOP, self::LATE, self::LEFT_BEHIND, self::DROPPED];

    /** Finales: ya no cambian (docs/11 §11.65). */
    public const FINAL_STATES = [self::DROPPED, self::LEFT_BEHIND, self::LATE, self::NOT_GOING];

    public static function isFinal(string $state): bool
    {
        return in_array($state, self::FINAL_STATES, true);
    }

    /** Estado recibido de un teléfono: los nombres viejos pasan a los nuevos. */
    public static function normalize(?string $state): ?string
    {
        return match ($state) {
            self::LEGACY_PICKED_UP => self::TRAVELLING,
            self::LEGACY_LEFT_BEHIND => self::LEFT_BEHIND,
            self::LEGACY_LATE => self::LATE,
            default => $state,
        };
    }

    protected $fillable = ['trip_id', 'user_id', 'stop_id', 'state', 'state_at', 'reported_at', 'children_count', 'child_ids', 'last_seen_at', 'gps_ok', 'set_by_server'];

    protected $casts = [
        'state_at' => 'datetime',
        'reported_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'gps_ok' => 'boolean',
        'set_by_server' => 'boolean',
        'children_count' => 'integer',
        'trip_id' => 'integer',
        'user_id' => 'integer',
        'stop_id' => 'integer',
    ];

    /**
     * Un cambio de estado cambia «Mi estado» del viaje: va al registro de
     * cambios como cambio del viaje (los envíos de cada Z, no).
     */
    protected static function booted(): void
    {
        static::saved(function (TripPassenger $passenger) {
            if ($passenger->wasRecentlyCreated || $passenger->wasChanged(['state', 'stop_id'])) {
                app(\App\Services\ChangeLog::class)->record('trips', [(int) $passenger->trip_id], \App\Services\ChangeLog::UPDATE);
            }
        });
    }

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
