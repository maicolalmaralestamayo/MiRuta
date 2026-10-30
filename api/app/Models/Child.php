<?php

namespace App\Models;

use App\Support\CardNumber;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Crypt;

/**
 * Hijo declarado por un trabajador. Mientras su solicitud está pendiente la
 * fila existe pero no cuenta; cuenta cuando la solicitud se aprueba.
 */
class Child extends Model
{
    use SoftDeletes;

    protected $table = 'children';

    protected $fillable = ['worker_id', 'first_name', 'last_name', 'card_number_encrypted', 'card_number_hash'];

    protected $hidden = ['card_number_encrypted', 'card_number_hash'];

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

    public function cardNumber(): CardNumber
    {
        return CardNumber::tryParse(Crypt::decryptString($this->card_number_encrypted));
    }
}
