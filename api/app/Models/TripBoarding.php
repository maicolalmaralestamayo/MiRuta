<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Registro de subida: uno por persona y trayecto (docs/11 §11.8 y §11.9).
 * Con sus hijos (trip_boarding_children) y, si subió alguien de otro
 * itinerario u otra Entidad, `outsider`.
 */
class TripBoarding extends Model
{
    use SoftDeletes;

    const METHOD_AUTOMATIC = 'automatic';
    const METHOD_SELF = 'self';
    const METHOD_QR = 'qr';
    const METHOD_MANUAL = 'manual';

    const OUTSIDER_ITINERARY = 'itinerary';
    const OUTSIDER_ENTITY = 'entity';

    protected $fillable = ['trip_leg_id', 'worker_id', 'method', 'marked_by', 'children_count', 'outsider', 'qr_kind', 'boarded_at'];

    protected $casts = [
        'children_count' => 'integer',
        'boarded_at' => 'datetime',
    ];

    public function tripLeg()
    {
        return $this->belongsTo(TripLeg::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function children()
    {
        return $this->hasMany(TripBoardingChild::class);
    }

    /**
     * @return int[]
     */
    public function childIds(): array
    {
        return $this->children()->orderBy('child_id')->pluck('child_id')->map(function ($id) {
            return (int) $id;
        })->all();
    }

    public function marker()
    {
        return $this->belongsTo(User::class, 'marked_by')->withTrashed();
    }
}
