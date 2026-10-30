<?php

namespace App\Serializers;

class TransportChiefSerializer extends RoleSerializer
{
    public function type(): string
    {
        return 'transport-chiefs';
    }
}
