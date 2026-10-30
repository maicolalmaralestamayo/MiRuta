<?php

namespace App\Http\Controllers;

use App\Models\Application;
use App\Models\Driver;
use App\Models\Worker;

class DriverController extends RoleController
{
    protected $model = Driver::class;

    protected $type = 'drivers';

    protected function leaveType(): string
    {
        return Application::TYPE_DRIVER_LEAVE;
    }

    protected function canRemoveOthers(Worker $user): bool
    {
        return $user->isTransportChief();
    }
}
