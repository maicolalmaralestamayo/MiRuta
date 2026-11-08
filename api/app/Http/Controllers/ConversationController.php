<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Services\Conversations;
use Illuminate\Http\Request;

/**
 * Conversaciones con el desarrollador (docs/11 §11.46 y §11.50): cada uno ve
 * las suyas; el Administrador, todas (y las responde).
 */
class ConversationController extends Controller
{
    public const SORTABLE = ['id' => 'id', 'lastMessageAt' => 'last_message_at'];
    public const INCLUDABLE = ['user', 'topic'];

    public function __construct(private Conversations $conversations)
    {
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, self::SORTABLE, ['mine', 'unread'], self::INCLUDABLE, '-lastMessageAt');
        $user = $request->user();
        $query = Conversation::query();

        if (! $user->isAdmin() || $parameters->filter('mine') === 'true') {
            $query->where('user_id', $user->id);
        }

        if ($parameters->filter('unread') === 'true') {
            $query->where(fn ($q) => $q->where(fn ($q) => $q->where('user_id', $user->id)->where('unread_by_user', true))
                ->orWhere(fn ($q) => $q->where('user_id', '<>', $user->id)->where('unread_by_developer', true)));
        }

        return $this->paginate($request, $query, $parameters, self::SORTABLE);
    }

    public function show(Request $request, $id)
    {
        return $this->respond($request, $this->find($request, $id), QueryParameters::readIncludes($request, self::INCLUDABLE));
    }

    /**
     * Abre una conversación: relationships.topic (motivo) y attributes.body (primer mensaje).
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'conversations', [
            'attributes.body' => ['required', 'string'],
        ] + $this->relationshipRules('topic', 'conversation-topics', 'conversation_topics', true));
        $conversation = $this->conversations->open($request->user(), $this->relationshipId($data, 'topic'), $data['attributes']['body']);

        return $this->created($request, $conversation->fresh(), 'conversations');
    }

    /**
     * Mensajes (del más antiguo al más nuevo; filter[after]=id para los nuevos).
     * Quien los consulta los da por leídos.
     */
    public function messages(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $after = $request->input('filter.after');

        if ($after !== null && ! ctype_digit((string) $after)) {
            throw JsonApiException::badRequest('filter[after] debe ser un id de mensaje.', 'filter[after]');
        }

        $messages = ConversationMessage::where('conversation_id', $conversation->id)
            ->when($after !== null, fn ($q) => $q->where('id', '>', (int) $after))
            ->orderBy('id')->limit(500)->get();
        $this->conversations->markRead($conversation, $request->user());

        return JsonApiResponse::make((new Document($request))->list($messages));
    }

    public function storeMessage(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $data = $this->validateResource($request, 'conversation-messages', ['attributes.body' => ['required', 'string']]);
        $message = $this->conversations->write($conversation, $request->user(), $data['attributes']['body']);

        return $this->created($request, $message, 'conversation-messages');
    }

    private function find(Request $request, $id): Conversation
    {
        $conversation = Conversation::findOrFail($id);

        if (! $this->conversations->canSee($request->user(), $conversation)) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La conversación no existe.');
        }

        return $conversation;
    }
}
