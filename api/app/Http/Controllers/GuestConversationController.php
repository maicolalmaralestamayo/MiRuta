<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\Conversation;
use App\Models\ConversationMessage;
use App\Services\Chats;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Hablar con el desarrollador sin cuenta, desde una instalación de la app
 * (cabecera X-Installation). El Administrador responde desde sus
 * conversaciones normales (docs/08-version-2.md §8.7).
 */
class GuestConversationController extends Controller
{
    /** @var Chats */
    private $chats;

    public function __construct(Chats $chats)
    {
        $this->chats = $chats;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], [], ['topic'], '-createdAt');
        $query = Conversation::where('installation_id', $this->installation($request)->id)->whereNull('opened_by');
        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'conversations', array_merge($this->chats->messageRules(), [
            'attributes.guestName' => ['required', 'string', 'max:150', 'regex:/\S/'],
            'attributes.guestPhone' => ['required', 'string', 'regex:/^\+?[0-9 ()\-]{7,20}$/'],
            'relationships.topic.data.type' => ['required', 'in:conversation-topics'],
            'relationships.topic.data.id' => ['required', 'exists:conversation_topics,id,deleted_at,NULL'],
        ]));
        $attributes = $data['attributes'];

        $conversation = $this->chats->openGuestConversation(
            $this->installation($request),
            (int) $data['relationships']['topic']['data']['id'],
            trim($attributes['guestName']),
            trim($attributes['guestPhone']),
            trim($attributes['body'])
        );

        return JsonApiResponse::make((new Document($request))->resource($conversation->fresh()), 201);
    }

    public function messages(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['since'], [], 'createdAt');
        $query = ConversationMessage::where('conversation_id', $conversation->id);

        if ($since = $parameters->filter('since')) {
            $query->where('created_at', '>', Carbon::parse($since)->setTimezone(config('app.timezone')));
        }

        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator));
    }

    public function storeMessage(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $data = $this->validateResource($request, 'conversation-messages', $this->chats->messageRules());
        $message = $this->chats->addGuestMessage($this->installation($request), $conversation, trim($data['attributes']['body']));

        return JsonApiResponse::make((new Document($request))->resource($message->fresh()), 201);
    }

    private function find(Request $request, $id): Conversation
    {
        $conversation = Conversation::where('installation_id', $this->installation($request)->id)->whereNull('opened_by')->find($id);

        if (! $conversation) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La conversación no existe.');
        }

        return $conversation;
    }

    private function installation(Request $request)
    {
        return $request->attributes->get('installation');
    }
}
