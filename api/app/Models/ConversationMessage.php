<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Mensaje de una conversación. Se borra físicamente al caducar.
 */
class ConversationMessage extends Model
{
    protected $fillable = ['conversation_id', 'user_id', 'body'];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }
}
