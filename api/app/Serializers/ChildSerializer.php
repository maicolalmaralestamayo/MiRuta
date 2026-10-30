<?php

namespace App\Serializers;

use App\Services\ChildEligibility;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Nombre y apellidos son públicos; el carné y la fecha límite (que revela la
 * fecha de nacimiento) solo los ven el padre o madre y el Administrador.
 */
class ChildSerializer extends Serializer
{
    public function type(): string
    {
        return 'children';
    }

    public function attributes(Model $child, Request $request): array
    {
        $attributes = [
            'firstName' => $child->first_name,
            'lastName' => $child->last_name,
        ];

        if ($this->canSeePrivateData($child, $request)) {
            $attributes['cardNumber'] = $child->cardNumber()->value();
        }

        return $attributes;
    }

    public function toOneRelationships(): array
    {
        return ['worker' => ['workers', 'worker_id', 'worker']];
    }

    public function meta(Model $child, Request $request): array
    {
        $eligibility = app(ChildEligibility::class);
        $card = $child->cardNumber();
        $meta = [
            'declared' => $child->newQuery()->declared()->whereKey($child->id)->exists(),
            'eligible' => $eligibility->isEligible($card),
        ];

        if ($this->canSeePrivateData($child, $request)) {
            $meta['eligibleUntil'] = $eligibility->eligibleUntil($card)->toDateString();
        }

        return $meta;
    }

    private function canSeePrivateData(Model $child, Request $request): bool
    {
        $viewer = $request->user();

        return $viewer && ($viewer->is_admin || (int) $viewer->id === (int) $child->worker_id);
    }
}
