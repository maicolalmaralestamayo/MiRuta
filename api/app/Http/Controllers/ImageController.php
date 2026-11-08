<?php

namespace App\Http\Controllers;

use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Services\Access;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Imagen opcional de una Entidad, un itinerario o una parada (multipart, campo «image»).
 */
class ImageController extends Controller
{
    public const MODELS = ['entities' => Entity::class, 'itineraries' => Itinerary::class, 'stops' => Stop::class];

    public function __construct(private Access $access)
    {
    }

    public function upload(Request $request, Settings $settings, Uploads $uploads, string $resource, $id)
    {
        $model = $this->manageable($request, $resource, $id);
        $this->validateRequest($request, [
            'image' => ['required', 'file', 'image', 'mimes:jpeg,png', 'max:'.$settings->int('tamano_foto')],
        ]);
        $previous = $model->image_path;
        $model->image_path = $uploads->store($request->file('image'), 'images');
        $model->save();
        $uploads->delete($previous);

        return $this->respond($request, $model->fresh());
    }

    public function destroy(Request $request, Uploads $uploads, string $resource, $id)
    {
        $model = $this->manageable($request, $resource, $id);
        $uploads->delete($model->image_path);
        $model->image_path = null;
        $model->save();

        return $this->noContent();
    }

    private function manageable(Request $request, string $resource, $id): Model
    {
        $model = (self::MODELS[$resource])::findOrFail($id);
        $user = $request->user();
        $chiefOf = $this->access->chiefItineraryId($user);
        $allowed = $this->access->isAdmin($user)
            || ($resource === 'stops' && $chiefOf !== null && ItineraryStop::where('itinerary_id', $chiefOf)->where('stop_id', $model->id)->exists());

        if (! $allowed) {
            throw Access::forbidden('No puede cambiar esta imagen.');
        }

        return $model;
    }
}
