<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use App\Models\ConversationTopic;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Motivos de conversación. La denominación es única por destinatario.
 */
class ConversationTopicController extends NomenclatorController
{
    protected $model = ConversationTopic::class;

    protected $type = 'conversation-topics';

    protected $attributes = [
        'name' => 'name',
        'description' => 'description',
        'observation' => 'observation',
        'recipient' => 'recipient',
    ];

    protected $filterable = ['name', 'recipient'];

    protected function rules(Request $request, ?Model $model): array
    {
        $rules = parent::rules($request, $model);
        $rules['attributes.name'] = [$model ? 'sometimes' : 'required', 'string', 'max:100'];
        $rules['attributes.recipient'] = [$model ? 'sometimes' : 'required', 'in:itinerary_chiefs,transport_chiefs,developer'];

        return $rules;
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        parent::applyFilters($query, $parameters, $request);

        if ($recipient = $parameters->filter('recipient')) {
            $query->where('recipient', $recipient);
        }
    }

    protected function restorable(array $data): ?Model
    {
        $attributes = $data['attributes'];

        return ConversationTopic::onlyTrashed()
            ->where('name', trim($attributes['name']))
            ->where('recipient', $attributes['recipient'])
            ->first();
    }
}
