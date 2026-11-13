<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * La persona en un itinerario de una de sus Entidades (docs/11 §11.58): su
 * parada en él (opcional) y si es Jefe de ese itinerario. Una persona puede
 * estar en varios itinerarios de cada Entidad y es Jefe de uno solo.
 */
class WorkerItinerary extends Model
{
    protected $fillable = ['worker_id', 'user_id', 'itinerary_id', 'stop_id', 'is_chief'];

    protected $casts = [
        'is_chief' => 'boolean',
        'worker_id' => 'integer',
        'user_id' => 'integer',
        'itinerary_id' => 'integer',
        'stop_id' => 'integer',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }
}
