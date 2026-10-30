<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Datos propios de un tipo de solicitud (subtipo de applications).
 */
class AbsenceApplication extends Model
{
    use SoftDeletes;

    protected $primaryKey = 'application_id';

    public $incrementing = false;

    protected $casts = [
        'starts_on' => 'date',
        'ends_on' => 'date',
    ];

    protected $fillable = ['application_id', 'absence_type_id', 'starts_on', 'ends_on', 'observation'];

    public function application()
    {
        return $this->belongsTo(Application::class);
    }

    public function absenceType()
    {
        return $this->belongsTo(AbsenceType::class)->withTrashed();
    }
}
