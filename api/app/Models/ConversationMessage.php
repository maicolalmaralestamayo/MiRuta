<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Mensaje de una conversación. Se borra físicamente al caducar.
 */
class ConversationMessage extends Model
{
    protected $fillable = ['conversation_id', 'worker_id', 'body'];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }
}
