<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Solicitud de entrar en una Entidad o en un itinerario (docs/11 §11.23 y §11.26).
 */
class Application extends Model
{
    use \App\Models\Concerns\LogsChanges;

    public const TYPE_ENTITY = 'entidad';
    public const TYPE_ITINERARY = 'itinerario';

    public const PENDING = 'pendiente';
    public const APPROVED = 'aprobada';
    public const REJECTED = 'rechazada';

    protected $fillable = [
        'user_id', 'type', 'status', 'entity_id', 'itinerary_id', 'stop_id', 'denial_reason_id', 'entity_denial_reason_id', 'itinerary_denial_reason_id',
        'resolution_note', 'resolved_by', 'resolved_at', 'seen_at',
    ];

    protected $casts = [
        'resolved_at' => 'datetime',
        'seen_at' => 'datetime',
        'user_id' => 'integer',
        'entity_id' => 'integer',
        'itinerary_id' => 'integer',
        'stop_id' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }

    /** Motivo de la 4.3.0 (ya no se usa; se conserva el dato). */
    public function denialReason()
    {
        return $this->belongsTo(DenialReason::class);
    }

    public function entityDenialReason()
    {
        return $this->belongsTo(EntityDenialReason::class);
    }

    public function itineraryDenialReason()
    {
        return $this->belongsTo(ItineraryDenialReason::class);
    }

    /** El motivo del rechazo, de la tabla de su tipo (o null). */
    public function rejectionReason(): ?Nomenclator
    {
        return $this->type === self::TYPE_ENTITY ? $this->entityDenialReason : $this->itineraryDenialReason;
    }

    public function resolver()
    {
        return $this->belongsTo(User::class, 'resolved_by');
    }
}
