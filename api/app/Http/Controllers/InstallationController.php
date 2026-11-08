<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Models\Installation;
use Carbon\Carbon;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * Instalaciones de la app. La app registra la suya la primera vez que la
 * necesita y guarda el secreto; con él puede recuperar el acceso sin sesión
 * («Olvidé algo»). El Administrador puede bloquearlas.
 */
class InstallationController extends Controller
{
    /**
     * Público. Devuelve el id y el secreto (solo esta vez) en meta.secret.
     */
    public function store(Request $request)
    {
        $data = $this->validateResource($request, 'installations', [
            'attributes.deviceModel' => ['nullable', 'string', 'max:100'],
            'attributes.androidVersion' => ['nullable', 'string', 'max:20'],
            'attributes.appVersionCode' => ['nullable', 'integer', 'min:1'],
        ]);
        $attributes = isset($data['attributes']) ? $data['attributes'] : [];
        $secret = Str::random(48);

        $installation = Installation::create([
            'secret_hash' => hash('sha256', $secret),
            'device_model' => isset($attributes['deviceModel']) ? $attributes['deviceModel'] : null,
            'android_version' => isset($attributes['androidVersion']) ? $attributes['androidVersion'] : null,
            'app_version_code' => isset($attributes['appVersionCode']) ? (int) $attributes['appVersionCode'] : null,
        ]);

        $document = (new Document($request))->resource($installation);
        $document['data']['meta'] = ['secret' => $secret, 'header' => $installation->id.'.'.$secret];

        return JsonApiResponse::make($document, 201);
    }

    /**
     * Solo el Administrador.
     */
    public function show(Request $request, $id)
    {
        $this->authorizeAdmin($request);

        return JsonApiResponse::make((new Document($request))->resource(Installation::findOrFail($id), ['user']));
    }

    /**
     * Solo el Administrador: bloquear o desbloquear (attributes.blocked).
     */
    public function update(Request $request, $id)
    {
        $this->authorizeAdmin($request);
        $installation = Installation::findOrFail($id);
        $data = $this->validateResource($request, 'installations', ['attributes.blocked' => ['required', 'boolean']]);

        $installation->blocked_at = $data['attributes']['blocked'] ? ($installation->blocked_at ?: Carbon::now()) : null;
        $installation->save();

        return JsonApiResponse::make((new Document($request))->resource($installation));
    }

    private function authorizeAdmin(Request $request): void
    {
        app(\App\Services\Access::class)->requireAdmin($request->user());
    }
}
