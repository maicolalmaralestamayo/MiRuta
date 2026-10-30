<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Conversation;
use App\Models\ConversationTopic;
use App\Models\Trip;
use App\Models\Worker;
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
    public function tripWithChat(Worker $user, $tripId): Trip
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
    public function visibleConversations(Worker $user): Builder
    {
        $query = Conversation::query();

        if ($user->isAdmin()) {
            return $query;
        }

        $chiefOf = $user->chiefItineraryIds();
        $isTransportChief = $user->isTransportChief();

        return $query->where(function (Builder $query) use ($user, $chiefOf, $isTransportChief) {
            $query->where('opened_by', $user->id);

            if ($chiefOf) {
                $query->orWhere(function (Builder $query) use ($chiefOf) {
                    $query->whereIn('itinerary_id', $chiefOf)->whereHas('topic', function (Builder $query) {
                        $query->where('recipient', ConversationTopic::RECIPIENT_ITINERARY_CHIEFS);
                    });
                });
            }

            if ($isTransportChief) {
                $query->orWhereHas('topic', function (Builder $query) {
                    $query->where('recipient', ConversationTopic::RECIPIENT_TRANSPORT_CHIEFS);
                });
            }
        });
    }

    public function openConversation(Worker $user, int $topicId): Conversation
    {
        $topic = ConversationTopic::findOrFail($topicId);
        $itineraryId = null;

        if ($topic->recipient === ConversationTopic::RECIPIENT_ITINERARY_CHIEFS) {
            if (! $user->itinerary_id) {
                throw new JsonApiException(422, 'NO_ITINERARY', 'Sin itinerario', 'Para escribir a los Jefes de itinerario hay que ser miembro de un itinerario.', ['pointer' => '/data/relationships/topic']);
            }

            $itineraryId = $user->itinerary_id;
        }

        return Conversation::create(['conversation_topic_id' => $topic->id, 'opened_by' => $user->id, 'itinerary_id' => $itineraryId]);
    }

    public function messageRules(): array
    {
        return ['attributes.body' => ['required', 'string', 'max:'.$this->settings->int('message_max_length')]];
    }
}
