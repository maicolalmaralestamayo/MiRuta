<?php

namespace App\Http\Controllers;

use App\Models\AbsenceType;

class AbsenceTypeController extends NomenclatorController
{
    protected $model = AbsenceType::class;

    protected $type = 'absence-types';

    protected $manageOperation = 'absence_types.manage';
}
