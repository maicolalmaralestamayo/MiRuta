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
        $parameters = QueryParameters::fromRequest($request, ['createdAt' => 'created_at'], ['since'], ['worker'], 'createdAt');
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

        $message = TripMessage::create(['trip_id' => $trip->id, 'worker_id' => $request->user()->id, 'body' => trim($data['attributes']['body'])]);

        return JsonApiResponse::make((new Document($request))->resource($message->fresh()), 201);
    }
}
