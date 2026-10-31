<?php

namespace App\Serializers;

use App\Services\ChildEligibility;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;

/**
 * Datos públicos del trabajador. El carné solo lo ven el propio trabajador
 * y el Administrador (docs/02-procesos.md §2.1, Privacidad).
 */
class WorkerSerializer extends Serializer
{
    public function type(): string
    {
        return 'workers';
    }

    public function attributes(Model $worker, Request $request): array
    {
        $attributes = [
            'firstName' => $worker->first_name,
            'lastName' => $worker->last_name,
            'sex' => $worker->sex,
            'photoUrl' => $worker->photo_path ? url($worker->photo_path) : null,
            'isAdmin' => $worker->is_admin,
            'active' => ! $worker->trashed(),
            'createdAt' => $this->date($worker->created_at),
        ];

        if ($request->user() && $request->user()->isAdmin()) {
            $attributes['appVersionCode'] = $worker->app_version_code;
        }

        if (self::canSeePrivateData($worker, $request)) {
            $attributes['mustChangePassword'] = (bool) $worker->must_change_password;
            $attributes = [
                'username' => $worker->username,
                'cardNumber' => Crypt::decryptString($worker->card_number_encrypted),
            ] + $attributes;
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
                'isTransportChief' => $worker->isTransportChief(),
                'driverId' => $worker->driverId() ? (string) $worker->driverId() : null,
                'chiefOfItineraries' => array_map('strval', $worker->chiefItineraryIds()),
            ],
        ];
    }

    public static function canSeePrivateData(Model $worker, Request $request): bool
    {
        $viewer = $request->user();

        return $viewer && ($viewer->is_admin || (int) $viewer->id === (int) $worker->id);
    }

    public function toOneRelationships(): array
    {
        return [
            'rank' => ['ranks', 'rank_id', 'rank'],
            'itinerary' => ['itineraries', 'itinerary_id', 'itinerary'],
            'stop' => ['stops', 'stop_id', 'stop'],
        ];
    }
}
