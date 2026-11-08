<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Absence extends Model
{
    protected $fillable = ['worker_id', 'absence_type_id', 'starts_on', 'ends_on', 'note'];

    protected $casts = ['starts_on' => 'date', 'ends_on' => 'date', 'worker_id' => 'integer'];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function absenceType()
    {
        return $this->belongsTo(AbsenceType::class);
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
