<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Solicitud (docs/11 §11.6 y §11.16): entrar en una Entidad, itinerario y
 * parada, o un rol. Las solicitudes no se borran: son el historial. Darse
 * de baja es una acción directa, sin solicitud.
 */
class Application extends Model
{
    use SoftDeletes;

    const STATUS_PENDING = 'pending';
    const STATUS_APPROVED = 'approved';
    const STATUS_REJECTED = 'rejected';
    const STATUS_CANCELLED = 'cancelled';

    const TYPE_ENTITY_MEMBERSHIP = 'entity_membership';
    const TYPE_ITINERARY_MEMBERSHIP = 'itinerary_membership';
    const TYPE_ROLE = 'role';

    const TYPES = [self::TYPE_ENTITY_MEMBERSHIP, self::TYPE_ITINERARY_MEMBERSHIP, self::TYPE_ROLE];

    protected $fillable = [
        'user_id', 'entity_id', 'type', 'status', 'itinerary_id', 'stop_id', 'role_id',
        'created_by', 'resolved_by', 'resolved_at', 'resolution_note',
    ];

    protected $casts = [
        'resolved_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class)->withTrashed();
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class)->withTrashed();
    }

    public function role()
    {
        return $this->belongsTo(Role::class)->withTrashed();
    }

    public function creator()
    {
        return $this->belongsTo(User::class, 'created_by')->withTrashed();
    }

    public function resolver()
    {
        return $this->belongsTo(User::class, 'resolved_by')->withTrashed();
    }

    /**
     * Pertenencia del solicitante en la Entidad (si ya la tiene).
     */
    public function worker(): ?Worker
    {
        return Worker::where('user_id', $this->user_id)->where('entity_id', $this->entity_id)->first();
    }

    public function isPending(): bool
    {
        return $this->status === self::STATUS_PENDING;
    }
}
