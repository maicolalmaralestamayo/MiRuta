<?php

namespace App\Serializers;

class VehicleTypeSerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'vehicle-types';
    }
}
