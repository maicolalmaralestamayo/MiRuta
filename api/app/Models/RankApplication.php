<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Datos propios de un tipo de solicitud (subtipo de applications).
 */
class RankApplication extends Model
{
    use SoftDeletes;

    protected $primaryKey = 'application_id';

    public $incrementing = false;

    protected $fillable = ['application_id', 'rank_id'];

    public function application()
    {
        return $this->belongsTo(Application::class);
    }

    public function rank()
    {
        return $this->belongsTo(Rank::class)->withTrashed();
    }
}
