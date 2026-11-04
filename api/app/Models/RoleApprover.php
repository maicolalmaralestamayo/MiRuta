<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class RoleApprover extends Model
{
    use SoftDeletes;

    protected $fillable = ['role_id', 'approver_role_id'];

    public function role()
    {
        return $this->belongsTo(Role::class);
    }

    public function approverRole()
    {
        return $this->belongsTo(Role::class, 'approver_role_id');
    }
}
