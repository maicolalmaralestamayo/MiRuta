<?php

namespace App\Console\Commands;

use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Services\Settings;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Borra las conversaciones cuyo último mensaje (o su creación, si no tienen)
 * es más antiguo que conversation_retention_days (7.27).
 */
class PurgeExpiredConversations extends Command
{
    protected $signature = 'chats:purge-expired';

    protected $description = 'Borra las conversaciones caducadas';

    public function handle(Settings $settings)
    {
        $limit = Carbon::now()->subDays($settings->int('conversation_retention_days'));
        $expired = Conversation::query()
            ->whereRaw('COALESCE((SELECT MAX(created_at) FROM conversation_messages WHERE conversation_id = conversations.id), conversations.created_at) < ?', [$limit])
            ->get();

        foreach ($expired as $conversation) {
            DB::transaction(function () use ($conversation) {
                ConversationMessage::where('conversation_id', $conversation->id)->delete();
                $conversation->delete();
            });
        }

        $this->info("Conversaciones borradas: {$expired->count()}");
    }
}
