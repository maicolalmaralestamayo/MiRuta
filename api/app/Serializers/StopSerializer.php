<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class StopSerializer extends Serializer
{
    public function type(): string
    {
        return 'stops';
    }

    public function attributes(Model $stop, Request $request): array
    {
        return [
            'landmark' => $stop->landmark,
            'street' => $stop->street,
            'crossStreet1' => $stop->cross_street_1,
            'crossStreet2' => $stop->cross_street_2,
            'latitude' => $stop->latitude,
            'longitude' => $stop->longitude,
            'address' => $stop->address(),
        ];
    }
}
