<?php

namespace Database\Seeders;

use App\Models\ConversationTopic;
use App\Models\Role;
use Illuminate\Database\Seeder;

/**
 * Motivos de conversación: dirigidos a un rol de partida (Jefe de
 * itinerario, Jefe de Transporte) o al desarrollador.
 */
class ConversationTopicSeeder extends Seeder
{
    public function run()
    {
        $topics = [
            RoleSeeder::ITINERARY_CHIEF => ['Reportar un problema', 'Reportar una queja', 'Solicitar información'],
            RoleSeeder::TRANSPORT_CHIEF => ['Reportar un problema', 'Reportar una queja', 'Solicitar información'],
        ];

        foreach ($topics as $roleName => $names) {
            $role = Role::where('name', $roleName)->first();

            if (! $role) {
                continue;
            }

            foreach ($names as $name) {
                ConversationTopic::withTrashed()->firstOrCreate(['name' => $name, 'recipient' => ConversationTopic::RECIPIENT_ROLE, 'role_id' => $role->id]);
            }
        }

        foreach (['Dar ideas', 'Reportar un error', 'Solicitar información'] as $name) {
            ConversationTopic::withTrashed()->firstOrCreate(['name' => $name, 'recipient' => ConversationTopic::RECIPIENT_DEVELOPER, 'role_id' => null]);
        }
    }
}
