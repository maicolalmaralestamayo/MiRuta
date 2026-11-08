<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Notificación pendiente de recoger por la app al sincronizar (GET /sync).
 */
class Notification extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = ['user_id', 'kind', 'title', 'body', 'data', 'created_at'];

    protected $casts = ['created_at' => 'datetime', 'user_id' => 'integer'];

    public function dataArray(): array
    {
        $data = $this->data ? json_decode($this->data, true) : null;

        return is_array($data) ? $data : [];
    }
}
