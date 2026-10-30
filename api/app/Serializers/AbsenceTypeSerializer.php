<?php

namespace App\Serializers;

class AbsenceTypeSerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'absence-types';
    }
}
