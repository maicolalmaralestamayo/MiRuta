<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Estado de un trabajador en un viaje (docs/11 §11.43 y §11.67). Lo calcula su
 * teléfono (o lo pone él a mano) y envía solo los cambios, con la hora de
 * captura; stop_id es la parada detectada por cercanía (docs/11 §11.65).
 */
class TripPassenger extends Model
{
    // Estados del trabajador, versión definitiva (docs/11 §11.67), iguales en la ida y en el regreso.
    /** A más del «Radio acercamiento» de todas las paradas del itinerario. */
    public const OUT_OF_ROUTE = 'fuera_itinerario';
    /** Entre el «Radio acercamiento» y el «Radio parada» de una parada, a pie, acercándose. */
    public const APPROACHING = 'acercandose';
    /** Entre el «Radio acercamiento» y el «Radio parada» de una parada, a pie, alejándose. */
    public const MOVING_AWAY = 'alejandose';
    /** A «Radio parada» o menos de una parada. */
    public const AT_STOP = 'en_parada';
    /** Su parada dejó de estar En espera antes de que llegara a ella. */
    public const LATE = 'llegada_tarde';
    /** Su parada dejó de estar En espera y él siguió En Parada. */
    public const LEFT_BEHIND = 'no_recogido';
    public const TRAVELLING = 'viajando';
    public const DROPPED = 'dejado';
    /** Solo a mano: avisa que no irá (nunca se calcula). */
    public const NOT_TRAVELLING = 'no_viajare';

    public const STATES = [self::OUT_OF_ROUTE, self::APPROACHING, self::MOVING_AWAY, self::AT_STOP, self::LATE, self::LEFT_BEHIND,
        self::TRAVELLING, self::DROPPED, self::NOT_TRAVELLING];

    /** Estados con parada (detectada por cercanía): las cantidades de cada parada de la línea. */
    public const STOP_STATES = [self::APPROACHING, self::MOVING_AWAY, self::AT_STOP, self::LATE, self::LEFT_BEHIND, self::TRAVELLING, self::DROPPED];

    /** Estados sin parada. */
    public const STOPLESS_STATES = [self::OUT_OF_ROUTE, self::NOT_TRAVELLING];

    /** Quien aún espera una parada (para No recogido / Llegada tarde puestos por el servidor). */
    public const WAITING_STATES = [self::APPROACHING, self::MOVING_AWAY, self::AT_STOP];

    /** El viaje terminó para él (fin de su ventana de viaje). */
    public const FINAL_STATES = [self::DROPPED, self::NOT_TRAVELLING];

    public static function isFinal(string $state): bool
    {
        return in_array($state, self::FINAL_STATES, true);
    }

    public static function name(?string $state): string
    {
        return [
            self::OUT_OF_ROUTE => 'Fuera de itinerario', self::APPROACHING => 'Acercándose a Parada', self::MOVING_AWAY => 'Alejándose de Parada',
            self::AT_STOP => 'En Parada', self::LATE => 'Llegada tarde', self::LEFT_BEHIND => 'No recogido', self::TRAVELLING => 'Viajando',
            self::DROPPED => 'Dejado', self::NOT_TRAVELLING => 'No viajaré',
        ][$state] ?? 'Sin estado';
    }

    protected $fillable = ['trip_id', 'user_id', 'stop_id', 'state', 'state_at', 'reported_at', 'manual', 'children_count', 'child_ids', 'last_seen_at', 'gps_ok', 'set_by_server'];

    protected $casts = [
        'state_at' => 'datetime',
        'reported_at' => 'datetime',
        'last_seen_at' => 'datetime',
        'gps_ok' => 'boolean',
        'set_by_server' => 'boolean',
        'manual' => 'boolean',
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
