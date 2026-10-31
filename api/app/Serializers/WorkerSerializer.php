<?php

namespace App\Serializers;

use App\Services\ChildEligibility;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Trabajador. Los nombres y la foto vienen de su cuenta. El Pase lo ven el
 * propio trabajador, el Jefe de su itinerario, los Jefes de Transporte de
 * su Entidad y el Administrador (docs/08-version-2.md §8.3).
 */
class WorkerSerializer extends Serializer
{
    public function type(): string
    {
        return 'workers';
    }

    public function attributes(Model $worker, Request $request): array
    {
        $user = $worker->user;
        $attributes = [
            'firstName' => $user ? $user->first_name : null,
            'middleName' => $user ? $user->middle_name : null,
            'firstSurname' => $user ? $user->first_surname : null,
            'secondSurname' => $user ? $user->second_surname : null,
            'fullName' => $user ? $user->fullName() : null,
            'photoUrl' => $user && $user->photo_path ? url($user->photo_path) : null,
            'sex' => $worker->sex,
            'active' => ! $worker->trashed(),
            'createdAt' => $this->date($worker->created_at),
        ];

        if (self::canSeePass($worker, $request)) {
            $attributes = ['pass' => $worker->pass] + $attributes + [
                // Cuenta creada por un superior y aún sin activar.
                'activated' => $user ? $user->isActivated() : false,
            ];
        }

        return $attributes;
    }

    public function meta(Model $worker, Request $request): array
    {
        if ($worker->trashed()) {
            return [];
        }

        return [
            'childrenCount' => app(ChildEligibility::class)->eligibleCount($worker),
            'roles' => [
                'isTransportChief' => $worker->transportChief()->exists(),
                'driverId' => ($id = $worker->driver()->value('id')) ? (string) $id : null,
                'chiefOfItineraries' => array_map('strval', $worker->itineraryChiefs()->pluck('itinerary_id')->all()),
            ],
        ];
    }

    public static function canSeePass(Model $worker, Request $request): bool
    {
        $viewer = $request->user();

        if (! $viewer) {
            return false;
        }

        return $viewer->isAdmin()
            || $viewer->workerId() === (int) $worker->id
            || $viewer->managesEntity($worker->entity_id)
            || ($worker->itinerary_id !== null && in_array((int) $worker->itinerary_id, $viewer->chiefItineraryIds(), true))
            || self::isApplyingToChiefsItinerary($worker, $viewer);
    }

    public function toOneRelationships(): array
    {
        return [
            'user' => ['users', 'user_id', 'user'],
            'entity' => ['entities', 'entity_id', 'entity'],
            'rank' => ['ranks', 'rank_id', 'rank'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }

    /**
     * El Jefe de itinerario ve el Pase de quien pide entrar en su itinerario,
     * para comprobar quién es.
     */
    private static function isApplyingToChiefsItinerary(Model $worker, $viewer): bool
    {
        $itineraries = $viewer->chiefItineraryIds();

        if ($itineraries === []) {
            return false;
        }

        return \App\Models\Application::where('worker_id', $worker->id)
            ->where('type', \App\Models\Application::TYPE_ITINERARY_MEMBERSHIP)
            ->where('status', \App\Models\Application::STATUS_PENDING)
            ->whereHas('itineraryApplication', function ($query) use ($itineraries) {
                $query->whereIn('itinerary_id', $itineraries);
            })
            ->exists();
    }
}
