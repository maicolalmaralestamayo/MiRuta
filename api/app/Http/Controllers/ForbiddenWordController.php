<?php

namespace App\Http\Controllers;

use App\Models\ForbiddenWord;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Palabras no permitidas en los usuarios. Solo las ve y gestiona el Administrador.
 */
class ForbiddenWordController extends NomenclatorController
{
    protected $model = ForbiddenWord::class;

    protected $type = 'forbidden-words';

    public function index(Request $request)
    {
        $this->ensureAdmin($request);

        return parent::index($request);
    }

    public function show(Request $request, $id)
    {
        $this->ensureAdmin($request);

        return parent::show($request, $id);
    }

    protected function rules(Request $request, ?Model $model): array
    {
        $rules = parent::rules($request, $model);
        $rules['attributes.name'][] = 'max:50';

        return $rules;
    }

    protected function beforeSave(Model $model, Request $request, bool $creating): void
    {
        parent::beforeSave($model, $request, $creating);
        $model->name = mb_strtolower(trim($model->name), 'UTF-8');
    }

    private function ensureAdmin(Request $request): void
    {
        if (! $request->user()->isAdmin()) {
            throw new \Illuminate\Auth\Access\AuthorizationException();
        }
    }
}
