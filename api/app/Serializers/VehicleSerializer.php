<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class VehicleSerializer extends Serializer
{
    public function type(): string
    {
        return 'vehicles';
    }

    public function attributes(Model $vehicle, Request $request): array
    {
        return [
            'plate' => $vehicle->plate,
            'seats' => $vehicle->seats,
            'standingCapacity' => $vehicle->standing_capacity,
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'entity' => ['entities', 'entity_id', 'entity'],
            'vehicleType' => ['vehicle-types', 'vehicle_type_id', 'vehicleType'],
            'driver' => ['workers', 'driver_id', 'driver'],
        ];
    }

    public function meta(Model $vehicle, Request $request): array
    {
        return ['totalCapacity' => $vehicle->totalCapacity()];
    }
}
