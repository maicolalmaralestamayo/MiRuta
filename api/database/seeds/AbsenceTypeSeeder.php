<?php

use App\Models\AbsenceType;
use Illuminate\Database\Seeder;

class AbsenceTypeSeeder extends Seeder
{
    public function run()
    {
        foreach (['Vacaciones', 'Enfermedad', 'Licencia', 'Otra'] as $name) {
            AbsenceType::withTrashed()->firstOrCreate(['name' => $name]);
        }
    }
}
