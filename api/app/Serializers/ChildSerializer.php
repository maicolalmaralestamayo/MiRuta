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
            'middleName' => $child->middle_name,
            'firstSurname' => $child->first_surname,
            'secondSurname' => $child->second_surname,
            'fullName' => $child->fullName(),
        ];

        if (self::canSeePrivateData($child, $request)) {
            $attributes['birthDate'] = $child->birth_date->toDateString();
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
        $meta = [
            'declared' => $child->newQuery()->declared()->whereKey($child->id)->exists(),
            'eligible' => $eligibility->isChildEligible($child),
        ];

        if (self::canSeePrivateData($child, $request)) {
            $meta['eligibleUntil'] = $eligibility->childEligibleUntil($child)->toDateString();
        }

        return $meta;
    }

    /**
     * La fecha de nacimiento la ven el padre o la madre, sus jefes (los de
     * su itinerario y los Jefes de Transporte de su Entidad) y el Administrador.
     */
    public static function canSeePrivateData(Model $child, Request $request): bool
    {
        $viewer = $request->user();

        if (! $viewer) {
            return false;
        }

        if ($viewer->isAdmin() || $viewer->workerId() === (int) $child->worker_id) {
            return true;
        }

        $worker = $child->worker;

        return $worker && ($viewer->managesEntity($worker->entity_id) || $viewer->isChiefOf($worker->itinerary_id ? (int) $worker->itinerary_id : null));
    }
}
