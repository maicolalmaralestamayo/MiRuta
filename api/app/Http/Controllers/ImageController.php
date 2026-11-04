<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiResponse;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\Stop;
use App\Services\Permissions;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Imágenes opcionales de Entidades, itinerarios y paradas (docs/11 §11.10),
 * como las fotos de perfil: multipart con el campo "image". Sin imagen, la
 * app muestra un ícono.
 */
class ImageController extends Controller
{
    /** [recurso => [modelo, operación, ¿es de una Entidad?]] */
    const RESOURCES = [
        'entities' => [Entity::class, 'entities.manage', false],
        'itineraries' => [Itinerary::class, 'itineraries.manage', true],
        'stops' => [Stop::class, 'stops.manage', true],
    ];

    public function upload(Request $request, Settings $settings, Uploads $uploads, string $resource, $id)
    {
        $model = $this->manageable($request, $resource, $id);
        $this->validate($request, [
            'image' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('photo_max_kb')],
        ]);

        $previous = $model->image_path;
        $model->image_path = $uploads->store($request->file('image'), 'images');
        $model->save();
        $uploads->delete($previous);

        return JsonApiResponse::make((new Document($request))->resource($model->fresh()));
    }

    public function destroy(Request $request, Uploads $uploads, string $resource, $id)
    {
        $model = $this->manageable($request, $resource, $id);
        $uploads->delete($model->image_path);
        $model->image_path = null;
        $model->save();

        return response('', 204);
    }

    private function manageable(Request $request, string $resource, $id): Model
    {
        list($class, $operation, $entityScoped) = self::RESOURCES[$resource];
        $model = $class::findOrFail($id);
        app(Permissions::class)->authorize($request->user(), $operation, $entityScoped ? (int) $model->entity_id : null);

        return $model;
    }
}
