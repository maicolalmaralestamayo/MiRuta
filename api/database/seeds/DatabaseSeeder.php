<?php

use Illuminate\Database\Seeder;

class DatabaseSeeder extends Seeder
{
    /**
     * Datos de referencia. Todos los seeders se pueden ejecutar varias veces.
     *
     * @return void
     */
    public function run()
    {
        $this->call(RankSeeder::class);
        $this->call(VehicleTypeSeeder::class);
        $this->call(AbsenceTypeSeeder::class);
        $this->call(ConversationTopicSeeder::class);
        $this->call(SettingDefinitionSeeder::class);
    }
}
