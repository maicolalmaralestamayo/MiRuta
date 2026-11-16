<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ItineraryStop extends Model
{
    use \App\Models\Concerns\LogsChanges;

    protected $table = 'itinerary_stop';

    protected $fillable = ['itinerary_id', 'stop_id', 'position'];

    protected $casts = ['itinerary_id' => 'integer', 'stop_id' => 'integer', 'position' => 'integer'];

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }
}
