<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ConversationTopic extends Model
{
    use SoftDeletes;

    /** A quienes tienen ese rol en la Entidad (o en el itinerario, si el rol es por itinerario). */
    const RECIPIENT_ROLE = 'role';
    const RECIPIENT_DEVELOPER = 'developer';

    protected $fillable = ['name', 'description', 'observation', 'recipient', 'role_id'];

    public function role()
    {
        return $this->belongsTo(Role::class)->withTrashed();
    }
}
