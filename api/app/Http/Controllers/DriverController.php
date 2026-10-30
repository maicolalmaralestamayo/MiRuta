<?php

namespace App\Http\Controllers;

use App\Models\Driver;

class DriverController extends RoleController
{
    protected $model = Driver::class;

    protected $type = 'drivers';
}
