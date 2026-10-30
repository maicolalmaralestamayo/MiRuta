<?php

namespace App\Http\Controllers;

use App\Models\TransportChief;

class TransportChiefController extends RoleController
{
    protected $model = TransportChief::class;

    protected $type = 'transport-chiefs';
}
