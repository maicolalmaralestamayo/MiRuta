<?php

namespace App\Serializers;

class DriverSerializer extends RoleSerializer
{
    public function type(): string
    {
        return 'drivers';
    }
}
