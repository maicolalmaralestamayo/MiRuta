<?php

use App\Models\ConversationTopic;
use Illuminate\Database\Seeder;

class ConversationTopicSeeder extends Seeder
{
    public function run()
    {
        $topics = [
            ConversationTopic::RECIPIENT_ITINERARY_CHIEFS => ['Reportar un problema', 'Reportar una queja', 'Solicitar información'],
            ConversationTopic::RECIPIENT_TRANSPORT_CHIEFS => ['Reportar un problema', 'Reportar una queja', 'Solicitar información'],
            ConversationTopic::RECIPIENT_DEVELOPER => ['Dar ideas', 'Reportar un error', 'Solicitar información'],
        ];

        foreach ($topics as $recipient => $names) {
            foreach ($names as $name) {
                ConversationTopic::withTrashed()->firstOrCreate(['name' => $name, 'recipient' => $recipient]);
            }
        }
    }
}
