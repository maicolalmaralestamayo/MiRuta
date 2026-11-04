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
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;

class ConversationController extends Controller
{
    const INCLUDABLE = ['topic', 'openedBy', 'itinerary', 'entity', 'installation'];

    /** @var Chats */
    private $chats;

    public function __construct(Chats $chats)
    {
        $this->chats = $chats;
    }

    public function index(Request $request)
    {
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at', 'lastMessageAt' => 'last_message_at'], ['topic', 'recipient', 'mine'], self::INCLUDABLE, '-lastMessageAt');
        $query = $this->chats->visibleConversations($request->user())
            ->select('conversations.*')
            ->selectSub(ConversationMessage::selectRaw('COALESCE(MAX(created_at), conversations.created_at)')->whereColumn('conversation_id', 'conversations.id'), 'last_message_at');

        if ($topic = $parameters->filter('topic')) {
            $query->where('conversation_topic_id', $topic);
        }

        if ($recipient = $parameters->filter('recipient')) {
            $query->whereHas('topic', function (Builder $query) use ($recipient) {
                $query->where('recipient', $recipient);
            });
        }

        if ($parameters->filter('mine') === 'true') {
            $query->where('opened_by', $request->user()->id);
        }

        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at', 'lastMessageAt' => 'last_message_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function show(Request $request, $id)
    {
        return JsonApiResponse::make((new Document($request))->resource($this->find($request, $id), QueryParameters::readIncludes($request, self::INCLUDABLE)));
    }

    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'conversations', [
            'relationships.topic.data.type' => ['required', 'in:conversation-topics'],
            'relationships.topic.data.id' => ['required', 'exists:conversation_topics,id,deleted_at,NULL'],
            'relationships.entity.data.type' => ['sometimes', 'in:entities'],
            'relationships.entity.data.id' => ['sometimes', 'integer'],
        ]);
        $conversation = $this->chats->openConversation($request->user(), (int) $data['relationships']['topic']['data']['id'],
            isset($data['relationships']['entity']['data']['id']) ? (int) $data['relationships']['entity']['data']['id'] : null);

        return JsonApiResponse::make((new Document($request))->resource($conversation->fresh()), 201);
    }

    public function messages(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['since'], ['author'], 'createdAt');
        $query = ConversationMessage::where('conversation_id', $conversation->id);

        if ($since = $parameters->filter('since')) {
            $query->where('created_at', '>', Carbon::parse($since)->setTimezone(config('app.timezone')));
        }

        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function storeMessage(Request $request)
    {
        $data = $this->validateResource($request, 'conversation-messages', array_merge($this->chats->messageRules(), [
            'relationships.conversation.data.type' => ['required', 'in:conversations'],
            'relationships.conversation.data.id' => ['required', 'integer'],
        ]));
        $conversation = $this->find($request, $data['relationships']['conversation']['data']['id']);
        $this->chats->ensureOpen($conversation);

        $message = ConversationMessage::create([
            'conversation_id' => $conversation->id,
            'user_id' => $request->user()->id,
            'body' => trim($data['attributes']['body']),
        ]);

        return JsonApiResponse::make((new Document($request))->resource($message->fresh()), 201);
    }

    /**
     * Cerrar o reabrir (attributes.closed). Quien la abrió o quien la recibe.
     */
    public function update(Request $request, $id)
    {
        $conversation = $this->find($request, $id);
        $data = $this->validateResource($request, 'conversations', ['attributes.closed' => ['required', 'boolean']]);
        $conversation->closed_at = $data['attributes']['closed'] ? ($conversation->closed_at ?: Carbon::now()) : null;
        $conversation->save();

        return JsonApiResponse::make((new Document($request))->resource($conversation));
    }

    private function find(Request $request, $id): Conversation
    {
        $conversation = $this->chats->visibleConversations($request->user())->find($id);

        if (! $conversation) {
            throw new JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'La conversación no existe o no puede verla.');
        }

        return $conversation;
    }
}
