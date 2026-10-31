<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Hijo declarado por un trabajador. Mientras su solicitud está pendiente la
 * fila existe pero no cuenta; cuenta cuando la solicitud se aprueba.
 */
class Child extends Model
{
    use SoftDeletes;

    protected $table = 'children';

    protected $fillable = ['worker_id', 'first_name', 'middle_name', 'first_surname', 'second_surname', 'birth_date'];

    protected $dates = ['birth_date'];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function childApplications()
    {
        return $this->hasMany(ChildApplication::class);
    }

    /**
     * Solo los niños con su declaración aprobada (y sin quitar).
     */
    public function scopeDeclared(Builder $query): Builder
    {
        return $query->whereExists(function ($query) {
            $query->selectRaw('1')
                ->from('child_applications')
                ->join('applications', 'applications.id', '=', 'child_applications.application_id')
                ->whereColumn('child_applications.child_id', 'children.id')
                ->where('applications.type', Application::TYPE_CHILD_ADDITION)
                ->where('applications.status', Application::STATUS_APPROVED);
        });
    }

    public function fullName(): string
    {
        return trim(implode(' ', [$this->first_name, $this->middle_name, $this->first_surname, $this->second_surname]));
    }
}
