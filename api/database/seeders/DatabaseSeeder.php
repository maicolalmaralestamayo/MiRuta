<?php

namespace Database\Seeders;

use App\Models\AbsenceType;
use App\Models\ConversationTopic;
use App\Models\EntityDenialReason;
use App\Models\ItineraryDenialReason;
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
        // Desde la 4.4.0 (docs/11 §11.65). En un servidor ya instalado no se borra nada.
        foreach ([['Ómnibus Yutong', 45, 15], ['Carro Dongfeng', 32, 9]] as [$name, $seats, $standing]) {
            VehicleType::firstOrCreate(['name' => $name], ['seats' => $seats, 'standing' => $standing]);
        }

        foreach (['Vacaciones', 'Enfermedad', 'Licencia', 'Otra'] as $name) {
            AbsenceType::firstOrCreate(['name' => $name]);
        }

        foreach (['Reportar un error', 'Dar ideas', 'Solicitar información'] as $name) {
            ConversationTopic::firstOrCreate(['name' => $name]);
        }

        // Motivos de rechazo separados por tipo de solicitud (docs/11 §11.65; también los crea la migración 4.4).
        foreach (['Usted no pertenece a nuestra entidad', 'No se pudo verificar su identidad', 'Otro motivo de rechazo'] as $name) {
            EntityDenialReason::firstOrCreate(['name' => $name]);
        }

        foreach (['Usted no pertenece a este itinerario', 'No se pudo verificar su identidad', 'Usted no pertenece a esta entidad',
            'El itinerario está sobrecargado', 'Otro motivo de rechazo'] as $name) {
            ItineraryDenialReason::firstOrCreate(['name' => $name]);
        }

        foreach (['Rotura', 'Tráfico', 'Semáforo', 'Combustible', 'Accidente', 'Otra'] as $name) {
            DetentionCause::firstOrCreate(['name' => $name]);
        }
    }
}
