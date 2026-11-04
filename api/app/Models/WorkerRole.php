<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Rol de una persona en una Entidad (en su pertenencia). Si el rol es por
 * itinerario, lleva el itinerario (un Jefe de itinerario lo es de uno solo
 * en cada Entidad).
 */
class WorkerRole extends Model
{
    use SoftDeletes;

    protected $fillable = ['worker_id', 'role_id', 'itinerary_id'];

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function role()
    {
        return $this->belongsTo(Role::class)->withTrashed();
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class)->withTrashed();
    }
}
