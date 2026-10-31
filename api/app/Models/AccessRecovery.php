<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Crypt;

/**
 * Solicitud "No puedo entrar" (docs/08-version-2.md §8.6).
 */
class AccessRecovery extends Model
{
    use SoftDeletes;

    const STATUS_PENDING = 'pending';
    const STATUS_APPROVED = 'approved';
    const STATUS_REJECTED = 'rejected';
    const STATUS_COMPLETED = 'completed';
    const STATUS_EXPIRED = 'expired';

    protected $fillable = [
        'installation_id', 'forgot_username', 'forgot_password', 'entity_abbreviation', 'pass',
        'phone_encrypted', 'worker_id', 'status', 'resolved_by', 'resolved_at',
        'password_token_hash', 'expires_at', 'completed_at',
    ];

    protected $hidden = ['phone_encrypted', 'password_token_hash'];

    protected $casts = [
        'forgot_username' => 'boolean',
        'forgot_password' => 'boolean',
        'pass' => 'integer',
    ];

    protected $dates = ['resolved_at', 'expires_at', 'completed_at'];

    public function installation()
    {
        return $this->belongsTo(Installation::class);
    }

    public function worker()
    {
        return $this->belongsTo(Worker::class)->withTrashed();
    }

    public function resolver()
    {
        return $this->belongsTo(User::class, 'resolved_by')->withTrashed();
    }

    public function phone(): ?string
    {
        return $this->phone_encrypted ? Crypt::decryptString($this->phone_encrypted) : null;
    }

    public function isOpen(): bool
    {
        return in_array($this->status, [self::STATUS_PENDING, self::STATUS_APPROVED], true);
    }

    /**
     * Cierra la solicitud y borra el teléfono y el token.
     */
    public function close(string $status): void
    {
        $this->forceFill([
            'status' => $status,
            'phone_encrypted' => null,
            'password_token_hash' => null,
            'completed_at' => $status === self::STATUS_COMPLETED ? Carbon::now() : $this->completed_at,
        ])->save();
    }
}
