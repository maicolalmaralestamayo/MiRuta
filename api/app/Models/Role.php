<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Rol configurable (docs/11 §11.16): un conjunto de operaciones, cada una
 * con su ámbito. El Administrador no es una fila (users.is_admin).
 */
class Role extends Model
{
    use SoftDeletes;

    protected $fillable = ['name', 'icon', 'requestable', 'is_default', 'itinerary_scoped'];

    protected $casts = [
        'requestable' => 'boolean',
        'is_default' => 'boolean',
        'itinerary_scoped' => 'boolean',
    ];

    public function permissions()
    {
        return $this->hasMany(RolePermission::class);
    }

    public function approvers()
    {
        return $this->hasMany(RoleApprover::class);
    }

    /**
     * @return int[] roles que aprueban sus solicitudes
     */
    public function approverRoleIds(): array
    {
        return array_map('intval', $this->approvers()->pluck('approver_role_id')->all());
    }

    public static function defaultRole(): ?self
    {
        return static::where('is_default', true)->first();
    }
}
