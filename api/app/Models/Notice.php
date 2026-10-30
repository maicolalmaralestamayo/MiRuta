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
    const TYPE_PASSWORD_RESET_REQUESTED = 'password_reset_requested';

    protected $fillable = ['worker_id', 'type', 'application_id', 'trip_id', 'password_reset_id', 'read_at'];

    protected $casts = [
        'read_at' => 'datetime',
    ];

    public function worker()
    {
        return $this->belongsTo(Worker::class);
    }

    public function passwordReset()
    {
        return $this->belongsTo(PasswordReset::class);
    }

    public function application()
    {
        return $this->belongsTo(Application::class);
    }
}
