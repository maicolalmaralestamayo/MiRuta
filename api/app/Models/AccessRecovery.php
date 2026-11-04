<?php

namespace App\Models;

use Carbon\Carbon;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Facades\Crypt;

/**
 * Solicitud «Olvidé algo» (docs/11 §11.7): carné y teléfono.
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
        'installation_id', 'forgot_username', 'forgot_password', 'identity_card_encrypted', 'identity_card_hash',
        'phone_encrypted', 'user_id', 'status', 'resolved_by', 'resolved_at',
        'password_encrypted', 'expires_at', 'completed_at',
    ];

    protected $hidden = ['phone_encrypted', 'password_encrypted', 'identity_card_encrypted', 'identity_card_hash'];

    protected $casts = [
        'forgot_username' => 'boolean',
        'forgot_password' => 'boolean',
    ];

    protected $dates = ['resolved_at', 'expires_at', 'completed_at'];

    public function installation()
    {
        return $this->belongsTo(Installation::class);
    }

    public function user()
    {
        return $this->belongsTo(User::class)->withTrashed();
    }

    public function resolver()
    {
        return $this->belongsTo(User::class, 'resolved_by')->withTrashed();
    }

    public function phone(): ?string
    {
        return $this->phone_encrypted ? Crypt::decryptString($this->phone_encrypted) : null;
    }

    public function identityCard(): ?string
    {
        return $this->identity_card_encrypted ? Crypt::decryptString($this->identity_card_encrypted) : null;
    }

    /**
     * Contraseña propuesta al aprobar (solo mientras está aprobada).
     */
    public function proposedPassword(): ?string
    {
        return $this->password_encrypted ? Crypt::decryptString($this->password_encrypted) : null;
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
            'identity_card_encrypted' => null,
            'password_encrypted' => null,
            'completed_at' => $status === self::STATUS_COMPLETED ? Carbon::now() : $this->completed_at,
        ])->save();
    }
}
