<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class RankSerializer extends NomenclatorSerializer
{
    public function type(): string
    {
        return 'ranks';
    }

    public function attributes(Model $rank, Request $request): array
    {
        return parent::attributes($rank, $request) + [
            'sortOrder' => $rank->sort_order,
            'iconUrl' => $rank->icon_path ? url($rank->icon_path) : null,
        ];
    }
}
