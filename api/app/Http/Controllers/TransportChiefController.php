<?php

namespace App\Http\Controllers;

use App\Models\Application;
use App\Models\TransportChief;
use App\Models\Worker;

class TransportChiefController extends RoleController
{
    protected $model = TransportChief::class;

    protected $type = 'transport-chiefs';

    protected function leaveType(): string
    {
        return Application::TYPE_TRANSPORT_CHIEF_LEAVE;
    }

    protected function canRemoveOthers(Worker $user): bool
    {
        return false;
    }
}
