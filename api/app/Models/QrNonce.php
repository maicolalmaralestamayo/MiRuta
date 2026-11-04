<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Código QR dinámico ya usado (un solo uso).
 */
class QrNonce extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'nonce', 'expires_at'];

    protected $casts = ['expires_at' => 'datetime'];
}
