<?php

namespace Database\Seeders;

use App\Models\VehicleType;
use Illuminate\Database\Seeder;

class VehicleTypeSeeder extends Seeder
{
    public function run()
    {
        foreach (['Guagua', 'Carro'] as $name) {
            VehicleType::withTrashed()->firstOrCreate(['name' => $name]);
        }
    }
}
