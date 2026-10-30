<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Crypt;

/**
 * Solicitud de restablecimiento de contraseña. El Administrador envía el
 * código al trabajador por WhatsApp; el teléfono y el código se borran al
 * terminar (usado, caducado o cancelado).
 */
class PasswordReset extends Model
{
    use SoftDeletes;

    const STATUS_PENDING = 'pending';
    const STATUS_SENT = 'sent';
    const STATUS_USED = 'used';
    const STATUS_EXPIRED = 'expired';
    const STATUS_CANCELLED = 'cancelled';

    protected $fillable = [
        'worker_id', 'phone_encrypted', 'code_encrypted', 'code_hash', 'status',
        'failed_attempts', 'expires_at', 'sent_by', 'sent_at', 'used_at',
    ];

    protected $hidden = ['phone_encrypted', 'code_encrypted', 'code_hash'];

    protected $casts = [
        'failed_attempts' => 'integer',
        'expires_at' => 'datetime',
        'sent_at' => 'datetime',
        'used_at' => 'datetime',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function isOpen(): bool
    {
        return in_array($this->status, [self::STATUS_PENDING, self::STATUS_SENT], true);
    }

    public function phone(): ?string
    {
        return $this->phone_encrypted ? Crypt::decryptString($this->phone_encrypted) : null;
    }

    public function code(): ?string
    {
        return $this->code_encrypted ? Crypt::decryptString($this->code_encrypted) : null;
    }

    /**
     * Cierra la solicitud y borra los datos personales.
     */
    public function close(string $status): void
    {
        $this->forceFill([
            'status' => $status,
            'phone_encrypted' => null,
            'code_encrypted' => null,
            'code_hash' => null,
        ])->save();
    }
}
