<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Models\Rank;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Jerarquías. El listado y el detalle son públicos (la pantalla de registro
 * los necesita); solo el Administrador las gestiona.
 */
class RankController extends NomenclatorController
{
    protected $model = Rank::class;

    protected $type = 'ranks';

    protected $attributes = [
        'name' => 'name',
        'description' => 'description',
        'observation' => 'observation',
        'precedence' => 'precedence',
    ];

    protected $sortable = ['id' => 'id', 'name' => 'name', 'precedence' => 'precedence'];

    protected $defaultSort = 'precedence';

    protected function rules(Request $request, ?Model $model): array
    {
        $unique = 'unique:ranks,precedence'.($model ? ",{$model->id}" : ',NULL').',id,deleted_at,NULL';

        return parent::rules($request, $model) + [
            'attributes.precedence' => [$model ? 'sometimes' : 'required', 'integer', 'min:1', 'max:65535', $unique],
        ];
    }

    public function uploadIcon(Request $request, Settings $settings, Uploads $uploads, $id)
    {
        $rank = Rank::findOrFail($id);
        $this->authorize('update', $rank);

        $this->validate($request, [
            'icon' => ['required', 'file', 'mimes:png,svg', 'max:'.$settings->int('rank_icon_max_kb')],
        ]);

        $previous = $rank->icon_path;
        $rank->icon_path = $uploads->store($request->file('icon'), 'ranks');
        $rank->save();
        $uploads->delete($previous);

        return JsonApiResponse::make((new Document($request))->resource($rank));
    }
}
