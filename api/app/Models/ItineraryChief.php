<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class ItineraryChief extends Model
{
    use SoftDeletes;

    protected $fillable = ['itinerary_id', 'worker_id'];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }
}
