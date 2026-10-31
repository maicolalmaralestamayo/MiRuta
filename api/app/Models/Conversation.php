<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Conversación de un trabajador con los Jefes de su itinerario, con los Jefes
 * de Transporte o con el desarrollador (el Administrador).
 */
class Conversation extends Model
{
    use SoftDeletes;

    protected $dates = ['closed_at'];

    protected $fillable = ['conversation_topic_id', 'opened_by', 'installation_id', 'guest_name', 'guest_phone_encrypted', 'itinerary_id', 'entity_id', 'closed_at'];

    public function topic()
    {
        return $this->belongsTo(ConversationTopic::class, 'conversation_topic_id')->withTrashed();
    }

    public function opener()
    {
        return $this->belongsTo(User::class, 'opened_by')->withTrashed();
    }

    public function installation()
    {
        return $this->belongsTo(Installation::class);
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }

    public function isGuest(): bool
    {
        return $this->opened_by === null;
    }

    public function isClosed(): bool
    {
        return $this->closed_at !== null;
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class)->withTrashed();
    }

    public function messages()
    {
        return $this->hasMany(ConversationMessage::class);
    }
}
