<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class RankSerializer extends Serializer
{
    public function type(): string
    {
        return 'ranks';
    }

    public function attributes(Model $rank, Request $request): array
    {
        return [
            'name' => $rank->name,
            'description' => $rank->description,
            'observation' => $rank->observation,
            'precedence' => $rank->precedence,
            'iconUrl' => $rank->icon_path ? url($rank->icon_path) : null,
        ];
    }
}
