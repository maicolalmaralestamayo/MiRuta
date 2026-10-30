<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Registro de subida. Puede haber varios por trabajador y trayecto; vale el
 * más reciente para la cantidad de niños.
 */
class TripBoarding extends Model
{
    use SoftDeletes;

    const METHOD_AUTOMATIC = 'automatic';
    const METHOD_SELF = 'self';
    const METHOD_QR = 'qr';
    const METHOD_MANUAL = 'manual';

    protected $fillable = ['trip_leg_id', 'worker_id', 'method', 'marked_by', 'children_count', 'boarded_at'];

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

    public function marker()
    {
        return $this->belongsTo(Worker::class, 'marked_by')->withTrashed();
    }
}
