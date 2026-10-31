<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Código de un solo uso para activar una cuenta creada por un superior.
 */
class ActivationCode extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'code_hash', 'failed_attempts', 'expires_at', 'created_by', 'used_at'];

    protected $hidden = ['code_hash'];

    protected $dates = ['expires_at', 'used_at'];

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
