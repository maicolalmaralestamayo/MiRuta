<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Mensaje del chat de un viaje. Se borra físicamente.
 */
class TripMessage extends Model
{
    protected $fillable = ['trip_id', 'user_id', 'body'];

    public function trip()
    {
        return $this->belongsTo(Trip::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }
}
