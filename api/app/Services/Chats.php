<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Conversation;
use App\Models\ConversationTopic;
use App\Models\Trip;
use App\Models\ConversationMessage;
use App\Models\Installation;
use App\Models\User;
use Carbon\Carbon;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\Eloquent\Builder;

/**
 * Chats del viaje y conversaciones con motivo (docs/02-procesos.md §2.10).
 */
class Chats
{
    /** @var Trips */
    private $trips;

    /** @var Settings */
    private $settings;

    public function __construct(Trips $trips, Settings $settings)
    {
        $this->trips = $trips;
        $this->settings = $settings;
    }

    /**
     * Viaje con chat disponible: visible para el usuario y confirmado.
     */
    public function tripWithChat(User $user, $tripId): Trip
    {
        $trip = $this->trips->visibleTo($user)->find($tripId);

        if (! $trip) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puede verlo.');
        }

        if ($trip->status !== Trip::STATUS_CONFIRMED) {
            throw JsonApiException::conflict('CHAT_NOT_AVAILABLE', 'El chat solo está disponible mientras el viaje está confirmado.');
        }

        return $trip;
    }

    /**
     * Conversaciones que la persona puede ver: las que abrió y las dirigidas
     * a un rol que tiene (en esa Entidad y, si el rol es por itinerario, en
     * ese itinerario) con chat.role_conversations. El Administrador, todas.
     */
    public function visibleConversations(User $user): Builder
    {
        $query = Conversation::query();

        if ($user->isAdmin()) {
            return $query;
        }

        $held = DB::table('worker_roles AS wr')
            ->join('workers AS w', 'w.id', '=', 'wr.worker_id')
            ->join('role_permissions AS rp', 'rp.role_id', '=', 'wr.role_id')
            ->whereNull('wr.deleted_at')->whereNull('w.deleted_at')->whereNull('rp.deleted_at')
            ->where('w.user_id', $user->id)->where('rp.operation', 'chat.role_conversations')
            ->get(['wr.role_id', 'wr.itinerary_id', 'w.entity_id']);

        return $query->where(function (Builder $query) use ($user, $held) {
            $query->where('opened_by', $user->id);

            foreach ($held as $row) {
                $query->orWhere(function (Builder $query) use ($row) {
                    $query->where('entity_id', $row->entity_id)
                        ->whereHas('topic', function (Builder $query) use ($row) {
                            $query->where('recipient', ConversationTopic::RECIPIENT_ROLE)->where('role_id', $row->role_id);
                        });

                    if ($row->itinerary_id !== null) {
                        $query->where('itinerary_id', $row->itinerary_id);
                    }
                });
            }
        });
    }

    /**
     * Abre una conversación. Si va dirigida a un rol, es el de la Entidad
     * indicada (o la única a la que pertenece) y, si el rol es por
     * itinerario, el de su itinerario en esa Entidad.
     */
    public function openConversation(User $user, int $topicId, ?int $entityId = null): Conversation
    {
        $topic = ConversationTopic::findOrFail($topicId);
        $itineraryId = null;

        if ($topic->recipient === ConversationTopic::RECIPIENT_ROLE) {
            $entityId = $entityId !== null ? $entityId : $user->singleEntityId();
            $worker = $user->workerIn($entityId);

            if (! $worker) {
                throw new JsonApiException(422, 'ENTITY_REQUIRED', 'Sin Entidad', 'Para escribir a un rol hay que indicar una Entidad a la que pertenezca.', ['pointer' => '/data/relationships/entity']);
            }

            $role = $topic->role;

            if ($role && $role->itinerary_scoped) {
                if (! $worker->itinerary_id) {
                    throw new JsonApiException(422, 'NO_ITINERARY', 'Sin itinerario', 'Para escribir a ese rol hay que ser miembro de un itinerario.', ['pointer' => '/data/relationships/topic']);
                }

                $itineraryId = (int) $worker->itinerary_id;
            }
        } else {
            $entityId = null;
        }

        return Conversation::create([
            'conversation_topic_id' => $topic->id, 'opened_by' => $user->id,
            'itinerary_id' => $itineraryId, 'entity_id' => $entityId,
        ]);
    }

    /**
     * Conversación con el desarrollador sin cuenta, desde una instalación
     * (docs/08-version-2.md §8.7). El primer mensaje va con ella.
     */
    public function openGuestConversation(Installation $installation, int $topicId, string $name, string $phone, string $body): Conversation
    {
        $topic = ConversationTopic::findOrFail($topicId);

        if ($topic->recipient !== ConversationTopic::RECIPIENT_DEVELOPER) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Motivo no válido', 'Sin cuenta solo se puede escribir al desarrollador.', ['pointer' => '/data/relationships/topic']);
        }

        $this->ensureGuestRate($installation);

        return DB::transaction(function () use ($installation, $topic, $name, $phone, $body) {
            $conversation = Conversation::create([
                'conversation_topic_id' => $topic->id,
                'installation_id' => $installation->id,
                'guest_name' => $name,
                'guest_phone_encrypted' => Crypt::encryptString($phone),
            ]);
            ConversationMessage::create(['conversation_id' => $conversation->id, 'user_id' => null, 'body' => $body]);

            return $conversation;
        });
    }

    public function addGuestMessage(Installation $installation, Conversation $conversation, string $body): ConversationMessage
    {
        $this->ensureOpen($conversation);
        $this->ensureGuestRate($installation);

        return ConversationMessage::create(['conversation_id' => $conversation->id, 'user_id' => null, 'body' => $body]);
    }

    public function ensureOpen(Conversation $conversation): void
    {
        if ($conversation->isClosed()) {
            throw JsonApiException::conflict('CONVERSATION_CLOSED', 'La conversación está cerrada.');
        }
    }

    private function ensureGuestRate(Installation $installation): void
    {
        $limit = $this->settings->int('guest_messages_max_per_hour');
        $sent = ConversationMessage::whereNull('user_id')
            ->whereIn('conversation_id', Conversation::where('installation_id', $installation->id)->select('id'))
            ->where('created_at', '>=', Carbon::now()->subHour())
            ->count();

        if ($sent >= $limit) {
            throw new JsonApiException(429, 'TOO_MANY_REQUESTS', 'Demasiados mensajes', 'Espere un rato antes de escribir otro mensaje.');
        }
    }

    public function messageRules(): array
    {
        return ['attributes.body' => ['required', 'string', 'max:'.$this->settings->int('message_max_length')]];
    }
}
