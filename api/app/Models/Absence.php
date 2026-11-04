<?php

namespace App\Models;

use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Ausencia declarada por el propio trabajador, sin aprobación (docs/11
 * §11.12): mientras dura no cuenta como pasajero esperado y se pausa la baja
 * por inactividad.
 */
class Absence extends Model
{
    use SoftDeletes;

    protected $fillable = ['worker_id', 'absence_type_id', 'starts_on', 'ends_on', 'indefinite', 'note'];

    protected $casts = [
        'starts_on' => 'date',
        'ends_on' => 'date',
        'indefinite' => 'boolean',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function absenceType()
    {
        return $this->belongsTo(AbsenceType::class)->withTrashed();
    }

    /**
     * Las que incluyen la fecha.
     */
    public function scopeCovering(Builder $query, CarbonInterface $date): Builder
    {
        $day = $date->toDateString();

        return $query->where('starts_on', '<=', $day)->where(function (Builder $query) use ($day) {
            $query->where('indefinite', true)->orWhereNull('ends_on')->orWhere('ends_on', '>=', $day);
        });
    }

    public function covers(string $day): bool
    {
        return $this->starts_on->toDateString() <= $day
            && ($this->indefinite || $this->ends_on === null || $this->ends_on->toDateString() >= $day);
    }
}
