<?php

namespace App\Console\Commands;

use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Models\Notice;
use App\Services\Settings;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Borra las conversaciones cuyo último mensaje (o su creación, si no tienen)
 * es más antiguo que su caducidad (7.27): conversation_retention_days para
 * las de una cuenta y guest_conversation_retention_days para las abiertas sin
 * cuenta. También borra los avisos leídos hace más de read_notice_retention_days.
 */
class PurgeExpiredConversations extends Command
{
    protected $signature = 'chats:purge-expired';

    protected $description = 'Borra las conversaciones caducadas y los avisos leídos antiguos';

    public function handle(Settings $settings)
    {
        $deleted = $this->purge(false, Carbon::now()->subDays($settings->int('conversation_retention_days')))
            + $this->purge(true, Carbon::now()->subDays($settings->int('guest_conversation_retention_days')));

        $notices = Notice::whereNotNull('read_at')
            ->where('read_at', '<', Carbon::now()->subDays($settings->int('read_notice_retention_days')))
            ->delete();

        $this->info("Conversaciones borradas: {$deleted}. Avisos leídos borrados: {$notices}.");
    }

    private function purge(bool $guest, Carbon $limit): int
    {
        $expired = Conversation::query()
            ->when($guest, function ($query) {
                $query->whereNull('opened_by');
            }, function ($query) {
                $query->whereNotNull('opened_by');
            })
            ->whereRaw('COALESCE((SELECT MAX(created_at) FROM conversation_messages WHERE conversation_id = conversations.id), conversations.created_at) < ?', [$limit])
            ->get();

        foreach ($expired as $conversation) {
            DB::transaction(function () use ($conversation) {
                ConversationMessage::where('conversation_id', $conversation->id)->delete();
                $conversation->delete();
            });
        }

        return $expired->count();
    }
}
