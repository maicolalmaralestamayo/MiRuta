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

    protected $fillable = ['conversation_topic_id', 'opened_by', 'itinerary_id'];

    public function topic()
    {
        return $this->belongsTo(ConversationTopic::class, 'conversation_topic_id')->withTrashed();
    }

    public function opener()
    {
        return $this->belongsTo(Worker::class, 'opened_by')->withTrashed();
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
