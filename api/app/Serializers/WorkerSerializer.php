<?php

namespace App\Serializers;

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

        if (self::canSeePrivateData($worker, $request)) {
            $attributes = ['cardNumber' => Crypt::decryptString($worker->card_number_encrypted)] + $attributes;
        }

        return $attributes;
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
