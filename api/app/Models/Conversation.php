<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Conversación con el desarrollador (docs/11 §11.46): la responde el Administrador.
 */
class Conversation extends Model
{
    protected $fillable = ['user_id', 'conversation_topic_id', 'last_message_at', 'unread_by_developer', 'unread_by_user'];

    protected $casts = [
        'last_message_at' => 'datetime',
        'unread_by_developer' => 'boolean',
        'unread_by_user' => 'boolean',
        'user_id' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function topic()
    {
        return $this->belongsTo(ConversationTopic::class, 'conversation_topic_id');
    }
}
