<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Ausencia de una persona en uno o varios de sus itinerarios (docs/11 §11.61).
 * Sin fecha final es indefinida: dura hasta que la persona la termine. Las
 * ausencias de la 4.1.0 conservan worker_id (su Entidad).
 */
class Absence extends Model
{
    protected $fillable = ['user_id', 'worker_id', 'absence_type_id', 'starts_on', 'ends_on', 'note'];

    protected $casts = ['starts_on' => 'date', 'ends_on' => 'date', 'worker_id' => 'integer', 'user_id' => 'integer'];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function absenceType()
    {
        return $this->belongsTo(AbsenceType::class);
    }

    public function itineraries()
    {
        return $this->belongsToMany(Itinerary::class, 'absence_itinerary');
    }

    /** @return int[] */
    public function itineraryIds(): array
    {
        return \Illuminate\Support\Facades\DB::table('absence_itinerary')->where('absence_id', $this->id)->pluck('itinerary_id')->map(fn ($id) => (int) $id)->all();
    }

    /**
     * Ausencias que cubren ese día.
     */
    public function scopeCovering($query, string $date)
    {
        return $query->where('starts_on', '<=', $date)->where(function ($q) use ($date) {
            $q->whereNull('ends_on')->orWhere('ends_on', '>=', $date);
        });
    }
}
