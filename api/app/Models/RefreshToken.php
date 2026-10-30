<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class RefreshToken extends Model
{
    use SoftDeletes;

    protected $fillable = ['worker_id', 'token_hash', 'device_name', 'expires_at', 'revoked_at', 'replaced_by_id'];

    protected $casts = [
        'expires_at' => 'datetime',
        'revoked_at' => 'datetime',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }
}
