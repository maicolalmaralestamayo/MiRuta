<?php

namespace App\Http\Controllers;

use App\JsonApi\QueryParameters;
use App\Models\ConversationTopic;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Motivos de conversación. La denominación es única por destinatario: un
 * rol (a quienes lo tienen en la Entidad o el itinerario) o el desarrollador.
 */
class ConversationTopicController extends NomenclatorController
{
    protected $model = ConversationTopic::class;

    protected $type = 'conversation-topics';

    protected $manageOperation = 'nomenclators.manage';

    protected $relationships = ['role' => ['roles', 'role_id']];

    protected $attributes = [
        'name' => 'name',
        'description' => 'description',
        'observation' => 'observation',
        'recipient' => 'recipient',
    ];

    protected $filterable = ['name', 'recipient', 'role'];

    protected $includable = ['role'];

    protected function rules(Request $request, ?Model $model): array
    {
        $rules = parent::rules($request, $model);
        $rules['attributes.name'] = [$model ? 'sometimes' : 'required', 'string', 'max:100'];
        $rules['attributes.recipient'] = [$model ? 'sometimes' : 'required', 'in:role,developer'];
        $recipient = $request->input('data.attributes.recipient', $model ? $model->recipient : null);
        $rules += $this->relationshipRules('role', 'roles', 'roles', ! $model && $recipient === ConversationTopic::RECIPIENT_ROLE, true);

        return $rules;
    }

    protected function applyFilters(Builder $query, QueryParameters $parameters, Request $request): void
    {
        parent::applyFilters($query, $parameters, $request);

        if ($recipient = $parameters->filter('recipient')) {
            $query->where('recipient', $recipient);
        }

        if ($role = $parameters->filter('role')) {
            $query->where('role_id', $role);
        }
    }

    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        parent::beforeSave($model, $request, $creating);

        if ($model->recipient === ConversationTopic::RECIPIENT_DEVELOPER) {
            $model->role_id = null;
        } elseif ($model->role_id === null) {
            throw new \App\JsonApi\JsonApiException(422, 'VALIDATION_ERROR', 'Falta el rol', 'Indique el rol al que se dirige.', ['pointer' => '/data/relationships/role']);
        }
    }

    protected function restorable(array $data): ?Model
    {
        $attributes = $data['attributes'];

        $roleId = isset($data['relationships']['role']['data']['id']) ? (int) $data['relationships']['role']['data']['id'] : null;

        return ConversationTopic::onlyTrashed()
            ->where('name', trim($attributes['name']))
            ->where('recipient', $attributes['recipient'])
            ->where('role_id', $attributes['recipient'] === ConversationTopic::RECIPIENT_ROLE ? $roleId : null)
            ->first();
    }
}
