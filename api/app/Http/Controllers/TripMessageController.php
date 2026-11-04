<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\JsonApi\QueryParameters;
use App\Models\TripMessage;
use App\Services\Chats;
use Carbon\Carbon;
use Illuminate\Http\Request;

/**
 * Chat del viaje: solo mientras el viaje está confirmado.
 */
class TripMessageController extends Controller
{
    public function index(Request $request, Chats $chats, $id)
    {
        $trip = $chats->tripWithChat($request->user(), $id);
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['since'], ['author'], 'createdAt');
        $query = TripMessage::where('trip_id', $trip->id);

        if ($since = $parameters->filter('since')) {
            $query->where('created_at', '>', Carbon::parse($since)->setTimezone(config('app.timezone')));
        }

        $paginator = $parameters->applySort($query, ['createdAt' => 'created_at'])
            ->paginate($parameters->pageSize(), ['*'], 'page', $parameters->pageNumber());

        return JsonApiResponse::make((new Document($request))->collection($paginator, $parameters->includes()));
    }

    public function store(Request $request, Chats $chats)
    {
        $data = $this->validateResource($request, 'trip-messages', array_merge($chats->messageRules(), [
            'relationships.trip.data.type' => ['required', 'in:trips'],
            'relationships.trip.data.id' => ['required', 'integer'],
        ]));
        $trip = $chats->tripWithChat($request->user(), $data['relationships']['trip']['data']['id']);

        $message = TripMessage::create(['trip_id' => $trip->id, 'user_id' => $request->user()->id, 'body' => trim($data['attributes']['body'])]);

        return JsonApiResponse::make((new Document($request))->resource($message->fresh()), 201);
    }

    /**
     * Borrar un mensaje: el propio, o el de otro con chat.delete_messages
     * sobre el itinerario del viaje.
     */
    public function destroy(Request $request, Chats $chats, \App\Services\Trips $trips, $id)
    {
        $user = $request->user();
        $message = TripMessage::whereIn('trip_id', $trips->visibleTo($user)->select('id'))->find($id);

        if (! $message) {
            throw new \App\JsonApi\JsonApiException(404, 'NOT_FOUND', 'No encontrado', 'El mensaje no existe o no puede verlo.');
        }

        if ((int) $message->user_id !== (int) $user->id) {
            $itineraryId = (int) \App\Models\Trip::whereKey($message->trip_id)->value('itinerary_id');
            app(\App\Services\Permissions::class)->authorize($user, 'chat.delete_messages', null, $itineraryId, 'Solo puede borrar sus propios mensajes.');
        }

        $message->delete();

        return response('', 204);
    }
}
