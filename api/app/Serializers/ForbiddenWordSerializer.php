<?php

namespace App\Serializers;

class ForbiddenWordSerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'forbidden-words';
    }
}
