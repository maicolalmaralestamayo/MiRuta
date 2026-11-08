<?php

namespace Database\Seeders;

use App\Models\AbsenceType;
use App\Models\ConversationTopic;
use App\Models\DenialReason;
use App\Models\DetentionCause;
use App\Models\VehicleType;
use Illuminate\Database\Seeder;

/**
 * Nomencladores de partida (el Administrador los cambia después en la app).
 * Los ajustes no se siembran: sus valores por omisión están en el código
 * (App\Support\SettingCatalog).
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
        foreach ([['Guagua', 40, 20], ['Microbús', 20, 5], ['Carro', 4, 0]] as [$name, $seats, $standing]) {
            VehicleType::firstOrCreate(['name' => $name], ['seats' => $seats, 'standing' => $standing]);
        }

        foreach (['Vacaciones', 'Enfermedad', 'Licencia', 'Otra'] as $name) {
            AbsenceType::firstOrCreate(['name' => $name]);
        }

        foreach (['Reportar un error', 'Dar ideas', 'Solicitar información'] as $name) {
            ConversationTopic::firstOrCreate(['name' => $name]);
        }

        foreach ([
            ['No trabaja en la Entidad', 'entidad'],
            ['Su parada no está en este itinerario', 'itinerario'],
            ['No hay capacidad en el vehículo', 'itinerario'],
            ['Datos incorrectos', null],
            ['Otro motivo', null],
        ] as [$name, $type]) {
            DenialReason::firstOrCreate(['name' => $name], ['application_type' => $type]);
        }

        foreach (['Rotura', 'Tráfico', 'Semáforo', 'Combustible', 'Accidente', 'Otra'] as $name) {
            DetentionCause::firstOrCreate(['name' => $name]);
        }
    }
}
