<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Datos propios de un tipo de solicitud (subtipo de applications).
 */
class ChildApplication extends Model
{
    use SoftDeletes;

    protected $primaryKey = 'application_id';

    public $incrementing = false;

    protected $fillable = ['application_id', 'child_id'];

    public function application()
    {
        return $this->belongsTo(Application::class);
    }

    public function child()
    {
        return $this->belongsTo(Child::class)->withTrashed();
    }
}
