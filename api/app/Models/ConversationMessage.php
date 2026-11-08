<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ConversationMessage extends Model
{
    protected $fillable = ['conversation_id', 'user_id', 'from_developer', 'body'];

    protected $casts = ['from_developer' => 'boolean', 'conversation_id' => 'integer'];

    public function conversation()
    {
        return $this->belongsTo(Conversation::class);
    }
}
