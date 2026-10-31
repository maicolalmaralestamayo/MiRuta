<?php

namespace App\Policies;

use App\Models\User;

class ReadOnlyPolicy extends ManagedPolicy
{
    protected function manages(User $user, $model = null): bool
    {
        return false;
    }
}
