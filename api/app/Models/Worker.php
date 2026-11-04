<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Pertenencia de una persona a una Entidad (docs/11 §11.6): en cada Entidad
 * tiene itinerario y parada (siempre juntos) y roles. Los nombres, el carné,
 * el usuario y la contraseña están en la persona (`user`). Borrado lógico =
 * baja de la Entidad (o pertenencia desactivada).
 */
class Worker extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'entity_id', 'itinerary_id', 'stop_id', 'itinerary_assigned_at'];

    protected $casts = [
        'entity_id' => 'integer',
        'itinerary_assigned_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }

    public function workerRoles()
    {
        return $this->hasMany(WorkerRole::class);
    }

    public function absences()
    {
        return $this->hasMany(Absence::class);
    }

    public function fullName(): string
    {
        return $this->user ? $this->user->fullName() : '';
    }
}
