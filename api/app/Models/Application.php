<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Solicitud. Las solicitudes no se borran: son el historial.
 */
class Application extends Model
{
    use SoftDeletes;

    const STATUS_PENDING = 'pending';
    const STATUS_APPROVED = 'approved';
    const STATUS_REJECTED = 'rejected';
    const STATUS_CANCELLED = 'cancelled';

    const TYPE_ITINERARY_MEMBERSHIP = 'itinerary_membership';
    const TYPE_ITINERARY_CHIEF = 'itinerary_chief';
    const TYPE_DRIVER = 'driver';
    const TYPE_TRANSPORT_CHIEF = 'transport_chief';
    const TYPE_RANK_CHANGE = 'rank_change';
    const TYPE_CHILD_ADDITION = 'child_addition';
    const TYPE_CHILD_REMOVAL = 'child_removal';
    const TYPE_ABSENCE = 'absence';
    const TYPE_ITINERARY_LEAVE = 'itinerary_leave';
    const TYPE_ITINERARY_CHIEF_LEAVE = 'itinerary_chief_leave';
    const TYPE_DRIVER_LEAVE = 'driver_leave';
    const TYPE_TRANSPORT_CHIEF_LEAVE = 'transport_chief_leave';
    const TYPE_ITINERARY_REMOVAL = 'itinerary_removal';

    /** Bajas voluntarias: se aprueban al crearse. */
    const LEAVE_TYPES = [
        self::TYPE_ITINERARY_LEAVE,
        self::TYPE_ITINERARY_CHIEF_LEAVE,
        self::TYPE_DRIVER_LEAVE,
        self::TYPE_TRANSPORT_CHIEF_LEAVE,
    ];

    /** Tipos que guardan itinerario (y parada) en itinerary_applications. */
    const ITINERARY_TYPES = [
        self::TYPE_ITINERARY_MEMBERSHIP,
        self::TYPE_ITINERARY_CHIEF,
        self::TYPE_ITINERARY_LEAVE,
        self::TYPE_ITINERARY_CHIEF_LEAVE,
        self::TYPE_ITINERARY_REMOVAL,
    ];

    protected $fillable = ['worker_id', 'type', 'status', 'resolved_by', 'resolved_at', 'resolution_note'];

    protected $casts = [
        'resolved_at' => 'datetime',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function resolver()
    {
        return $this->belongsTo(Worker::class, 'resolved_by')->withTrashed();
    }

    public function itineraryApplication()
    {
        return $this->hasOne(ItineraryApplication::class);
    }

    public function rankApplication()
    {
        return $this->hasOne(RankApplication::class);
    }

    public function childApplication()
    {
        return $this->hasOne(ChildApplication::class);
    }

    public function absenceApplication()
    {
        return $this->hasOne(AbsenceApplication::class);
    }

    /*
    | Datos del subtipo como si fueran del recurso (para la serialización).
    */

    public function getItineraryIdAttribute()
    {
        return $this->itineraryApplication ? $this->itineraryApplication->itinerary_id : null;
    }

    public function getStopIdAttribute()
    {
        return $this->itineraryApplication ? $this->itineraryApplication->stop_id : null;
    }

    public function getRankIdAttribute()
    {
        return $this->rankApplication ? $this->rankApplication->rank_id : null;
    }

    public function getChildIdAttribute()
    {
        return $this->childApplication ? $this->childApplication->child_id : null;
    }

    public function getAbsenceTypeIdAttribute()
    {
        return $this->absenceApplication ? $this->absenceApplication->absence_type_id : null;
    }

    public function getRequestedItineraryAttribute()
    {
        return $this->itineraryApplication ? $this->itineraryApplication->itinerary : null;
    }

    public function getRequestedStopAttribute()
    {
        return $this->itineraryApplication ? $this->itineraryApplication->stop : null;
    }

    public function getRequestedRankAttribute()
    {
        return $this->rankApplication ? $this->rankApplication->rank : null;
    }

    public function getRelatedChildAttribute()
    {
        return $this->childApplication ? $this->childApplication->child : null;
    }

    public function getRelatedAbsenceTypeAttribute()
    {
        return $this->absenceApplication ? $this->absenceApplication->absenceType : null;
    }

    public function isPending(): bool
    {
        return $this->status === self::STATUS_PENDING;
    }
}
