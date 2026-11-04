<?php

namespace App\Http\Controllers;

use App\Models\VehicleType;

class VehicleTypeController extends NomenclatorController
{
    protected $model = VehicleType::class;

    protected $type = 'vehicle-types';

    protected $manageOperation = 'nomenclators.manage';
}
