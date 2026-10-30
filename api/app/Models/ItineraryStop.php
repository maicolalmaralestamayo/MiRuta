<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ItineraryStop extends Model
{
    use SoftDeletes;

    protected $table = 'itinerary_stop';

    protected $fillable = ['itinerary_id', 'stop_id', 'position'];

    protected $casts = [
        'position' => 'integer',
    ];

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }
}
