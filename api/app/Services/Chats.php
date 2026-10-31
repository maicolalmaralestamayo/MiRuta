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
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El viaje no existe o no puedes verlo.');
        }

        if ($trip->status !== Trip::STATUS_CONFIRMED) {
            throw JsonApiException::conflict('CHAT_NOT_AVAILABLE', 'El chat solo está disponible mientras el viaje está confirmado.');
        }

        return $trip;
    }

    /**
     * Conversaciones que el usuario puede ver: las que abrió y las dirigidas a él.
     */
    public function visibleConversations(User $user): Builder
    {
        $query = Conversation::query();

        if ($user->isAdmin()) {
            return $query;
        }

        $chiefOf = $user->chiefItineraryIds();
        $isTransportChief = $user->isTransportChief();
        $entityId = $user->entityId();

        return $query->where(function (Builder $query) use ($user, $chiefOf, $isTransportChief, $entityId) {
            $query->where('opened_by', $user->id);

            if ($chiefOf) {
                $query->orWhere(function (Builder $query) use ($chiefOf) {
                    $query->whereIn('itinerary_id', $chiefOf)->whereHas('topic', function (Builder $query) {
                        $query->where('recipient', ConversationTopic::RECIPIENT_ITINERARY_CHIEFS);
                    });
                });
            }

            if ($isTransportChief) {
                $query->orWhere(function (Builder $query) use ($entityId) {
                    $query->where('entity_id', $entityId)->whereHas('topic', function (Builder $query) {
                        $query->where('recipient', ConversationTopic::RECIPIENT_TRANSPORT_CHIEFS);
                    });
                });
            }
        });
    }

    public function openConversation(User $user, int $topicId): Conversation
    {
        $topic = ConversationTopic::findOrFail($topicId);
        $worker = $user->workerModel();
        $itineraryId = null;
        $entityId = null;

        if ($topic->recipient === ConversationTopic::RECIPIENT_ITINERARY_CHIEFS) {
            if (! $worker || ! $worker->itinerary_id) {
                throw new JsonApiException(422, 'NO_ITINERARY', 'Sin itinerario', 'Para escribir a los Jefes de itinerario hay que ser miembro de un itinerario.', ['pointer' => '/data/relationships/topic']);
            }

            $itineraryId = (int) $worker->itinerary_id;
        }

        if ($topic->recipient === ConversationTopic::RECIPIENT_TRANSPORT_CHIEFS) {
            if (! $worker) {
                throw new JsonApiException(422, 'ENTITY_REQUIRED', 'Sin Entidad', 'Para escribir a los Jefes de Transporte hay que pertenecer a una Entidad.', ['pointer' => '/data/relationships/topic']);
            }

            $entityId = (int) $worker->entity_id;
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
            throw new JsonApiException(429, 'TOO_MANY_REQUESTS', 'Demasiados mensajes', 'Espera un rato antes de escribir otro mensaje.');
        }
    }

    public function messageRules(): array
    {
        return ['attributes.body' => ['required', 'string', 'max:'.$this->settings->int('message_max_length')]];
    }
}
