<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Aviso del servidor a un trabajador. La app lo recoge al sincronizar.
 */
class Notice extends Model
{
    use SoftDeletes;

    const TYPE_APPLICATION_RECEIVED = 'application_received';
    const TYPE_APPLICATION_RESOLVED = 'application_resolved';
    const TYPE_RESIGNATION = 'resignation';
    const TYPE_INACTIVITY_WARNING = 'inactivity_warning';
    const TYPE_INACTIVITY_REMOVAL = 'inactivity_removal';
    const TYPE_TRIP_NEEDS_REASSIGNMENT = 'trip_needs_reassignment';
    const TYPE_ROLE_ASSIGNED = 'role_assigned';
    const TYPE_ROLE_REMOVED = 'role_removed';
    const TYPE_ACCESS_RECOVERY_REQUESTED = 'access_recovery_requested';
    const TYPE_PASSWORD_EXPIRING = 'password_expiring';

    protected $fillable = ['user_id', 'type', 'application_id', 'trip_id', 'access_recovery_id', 'read_at'];

    protected $casts = [
        'read_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function accessRecovery()
    {
        return $this->belongsTo(AccessRecovery::class);
    }

    public function application()
    {
        return $this->belongsTo(Application::class);
    }
}
