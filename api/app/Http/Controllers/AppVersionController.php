<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\AppVersion;
use App\Models\Worker;
use App\Services\Settings;
use App\Services\Uploads;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Actualizaciones de la app desde el propio servidor. Solo el Administrador
 * publica versiones; la consulta de la última es pública (también la hace la
 * app antes de iniciar sesión).
 */
class AppVersionController extends Controller
{
    /**
     * Última versión. Con filter[currentVersionCode] indica si hay que
     * actualizar y si la actualización es obligatoria.
     */
    public function latest(Request $request)
    {
        $current = $request->input('filter.currentVersionCode');

        if ($current !== null && ! ctype_digit((string) $current)) {
            throw JsonApiException::badRequest('filter[currentVersionCode] debe ser un número entero.', 'filter[currentVersionCode]');
        }

        $latest = AppVersion::latest();
        $document = $latest ? (new Document($request))->resource($latest) : Document::fromArray(null);

        if ($current !== null) {
            $document['meta'] = [
                'updateAvailable' => $latest !== null && $latest->version_code > (int) $current,
                'mandatory' => AppVersion::isMandatoryAfter((int) $current),
            ];
        }

        return JsonApiResponse::make($document);
    }

    public function index(Request $request)
    {
        $this->ensureAdmin($request);
        $versions = AppVersion::orderBy('version_code', 'desc')->get();
        $document = (new Document($request))->list($versions);
        $document['meta'] = [
            'workersWithoutVersion' => Worker::whereNull('app_version_code')->count(),
        ];

        return JsonApiResponse::make($document);
    }

    /**
     * Publicar una versión (multipart/form-data): apk, versionName, versionCode,
     * notes y mandatory.
     */
    public function store(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->ensureAdmin($request);
        $this->validate($request, [
            'apk' => ['required', 'file', 'max:'.($settings->int('app_max_mb') * 1024)],
            'versionName' => ['required', 'string', 'max:20'],
            'versionCode' => ['required', 'integer', 'min:1'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'mandatory' => ['nullable', 'in:0,1,true,false'],
        ]);

        $file = $request->file('apk');

        if (strtolower($file->getClientOriginalExtension()) !== 'apk' || file_get_contents($file->getRealPath(), false, null, 0, 2) !== 'PK') {
            throw new JsonApiException(422, 'APK_INVALID', 'Archivo no válido', 'El archivo debe ser un APK de Android.', ['pointer' => '/apk']);
        }

        $code = (int) $request->input('versionCode');
        $latest = AppVersion::withTrashed()->max('version_code');

        if ($latest !== null && $code <= $latest) {
            throw new JsonApiException(422, 'VERSION_CODE_TOO_LOW', 'Versión no válida',
                "El versionCode debe ser mayor que el de la última versión publicada ({$latest}).", ['pointer' => '/versionCode']);
        }

        $sha256 = hash_file('sha256', $file->getRealPath());
        $size = $file->getSize();

        $version = DB::transaction(function () use ($request, $uploads, $file, $code, $sha256, $size) {
            return AppVersion::create([
                'version_name' => trim($request->input('versionName')),
                'version_code' => $code,
                'notes' => $request->input('notes'),
                'mandatory' => in_array($request->input('mandatory'), ['1', 'true', 1, true], true),
                'apk_path' => $uploads->store($file, 'apk', 'apk'),
                'size_bytes' => $size,
                'sha256' => $sha256,
                'published_by' => $request->user()->id,
            ]);
        });

        return JsonApiResponse::make((new Document($request))->resource($version->fresh()), 201);
    }

    /**
     * Retirar una versión (deja de ofrecerse y se borra el archivo).
     */
    public function destroy(Request $request, Uploads $uploads, $id)
    {
        $this->ensureAdmin($request);
        $version = AppVersion::findOrFail($id);
        $uploads->delete($version->apk_path);
        $version->delete();

        return response('', 204);
    }

    private function ensureAdmin(Request $request): void
    {
        if (! $request->user()->isAdmin()) {
            throw new JsonApiException(403, 'FORBIDDEN', 'Sin permiso', 'Solo el Administrador publica versiones de la app.');
        }
    }
}
