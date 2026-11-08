<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class QrNonce extends Model
{
    protected $fillable = ['user_id', 'nonce', 'purpose', 'reference_id', 'expires_at'];

    protected $casts = ['expires_at' => 'datetime'];
}
