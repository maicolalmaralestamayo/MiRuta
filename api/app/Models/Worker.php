<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Trabajador de una Entidad: el que viaja. Los nombres, el usuario y la
 * contraseña están en su cuenta (`user`). Inactivo = borrado lógico.
 */
class Worker extends Model
{
    use SoftDeletes;

    const SEX_FEMALE = 'F';
    const SEX_MALE = 'M';

    protected $fillable = ['user_id', 'entity_id', 'pass', 'sex', 'rank_id', 'itinerary_id', 'stop_id'];

    protected $casts = [
        'pass' => 'integer',
        'entity_id' => 'integer',
    ];

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class)->withTrashed();
    }

    public function rank()
    {
        return $this->belongsTo(Rank::class);
    }

    public function itinerary()
    {
        return $this->belongsTo(Itinerary::class);
    }

    public function stop()
    {
        return $this->belongsTo(Stop::class);
    }

    public function driver()
    {
        return $this->hasOne(Driver::class);
    }

    public function transportChief()
    {
        return $this->hasOne(TransportChief::class);
    }

    public function itineraryChiefs()
    {
        return $this->hasMany(ItineraryChief::class);
    }

    public function children()
    {
        return $this->hasMany(Child::class);
    }

    public function applications()
    {
        return $this->hasMany(Application::class);
    }

    /**
     * Id de su fila de chofer, si lo es.
     */
    public function driverId(): ?int
    {
        $id = Driver::where('worker_id', $this->id)->value('id');

        return $id === null ? null : (int) $id;
    }

    public function fullName(): string
    {
        return $this->user ? $this->user->fullName() : '';
    }

    /**
     * Trabajadores que puede ver esa cuenta: los de su Entidad (todos, para el Administrador).
     */
    public function scopeVisibleTo($query, User $user)
    {
        return $user->isAdmin() ? $query : $query->where('workers.entity_id', $user->entityId());
    }
}
