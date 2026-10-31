<?php

namespace Database\Seeders;

use App\Models\Rank;
use Illuminate\Database\Seeder;

class RankSeeder extends Seeder
{
    /**
     * Jerarquías, comunes a todas las Entidades, en su orden de presentación.
     * Solo sirven para las estadísticas.
     */
    const RANKS = [
        'Coronel',
        'Teniente coronel',
        'Mayor',
        'Funcionarios',
        'Capitán',
        'Primer teniente',
        'Teniente',
        'Subteniente',
        'Primer suboficial',
        'Segundo suboficial',
        'Tercer suboficial',
        'Suboficial',
        'Sargento de primera',
        'Sargento de segunda',
        'Sargento de tercera',
        'Cabo',
        'Trabajador civil',
        'Otra categoría',
    ];

    public function run()
    {
        foreach (self::RANKS as $index => $name) {
            Rank::withTrashed()->updateOrCreate(['name' => $name], ['sort_order' => $index + 1]);
        }
    }
}
