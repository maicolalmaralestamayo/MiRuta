<?php

namespace App\Http\Controllers;

use App\JsonApi\Document;
use App\JsonApi\JsonApiException;
use App\JsonApi\JsonApiResponse;
use App\Models\AppVersion;
use App\Models\AppVersionFile;
use App\Models\User;
use App\Services\Settings;
use App\Services\Uploads;
use App\Support\ApkInfo;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

/**
 * Actualizaciones de la app desde el propio servidor. Solo el Administrador
 * publica versiones, con un APK por tipo de procesador (64 y 32 bits) o uno
 * universal; la consulta de la última es pública (también la hace la app
 * antes de iniciar sesión).
 */
class AppVersionController extends Controller
{
    /** Campos del formulario de publicación para cada tipo de procesador. */
    const FILE_FIELDS = [
        'apkArm64' => AppVersionFile::ABI_ARM64,
        'apkArm32' => AppVersionFile::ABI_ARM32,
        'apkUniversal' => AppVersionFile::ABI_UNIVERSAL,
    ];

    /**
     * Última versión. Con filter[currentVersionCode] indica si hay que
     * actualizar y si la actualización es obligatoria. Con filter[abis]
     * (los que admite el teléfono, por preferencia) indica en meta.file qué
     * APK le corresponde.
     */
    public function latest(Request $request)
    {
        $current = $request->input('filter.currentVersionCode');

        if ($current !== null && ! ctype_digit((string) $current)) {
            throw JsonApiException::badRequest('filter[currentVersionCode] debe ser un número entero.', 'filter[currentVersionCode]');
        }

        $latest = AppVersion::latest();
        $document = $latest ? (new Document($request))->resource($latest) : Document::fromArray(null);
        $meta = [];

        if ($current !== null) {
            $meta['updateAvailable'] = $latest !== null && $latest->version_code > (int) $current;
            $meta['mandatory'] = AppVersion::isMandatoryAfter((int) $current);
        }

        if ($latest && ($abis = $request->input('filter.abis'))) {
            $file = $latest->fileFor(array_values(array_filter(array_map('trim', explode(',', (string) $abis)))));
            $meta['file'] = $file ? [
                'abi' => $file->abi,
                'downloadUrl' => url($file->apk_path),
                'sizeBytes' => $file->size_bytes,
                'sha256' => $file->sha256,
            ] : null;
        }

        if ($meta) {
            $document['meta'] = $meta;
        }

        return JsonApiResponse::make($document);
    }

    public function index(Request $request)
    {
        $this->ensureAdmin($request);
        $versions = AppVersion::orderBy('version_code', 'desc')->get();
        $document = (new Document($request))->list($versions);
        $document['meta'] = [
            'usersWithoutVersion' => User::whereNull('app_version_code')->count(),
        ];

        return JsonApiResponse::make($document);
    }

    /**
     * Publicar una versión (multipart/form-data): apkArm64, apkArm32 y/o
     * apkUniversal (al menos uno), versionName, versionCode, notes y mandatory.
     */
    public function store(Request $request, Settings $settings, Uploads $uploads)
    {
        $this->ensureAdmin($request);
        $max = $settings->int('tamano_apk') * 1024;
        $this->validateRequest($request, [
            'apkArm64' => ['nullable', 'file', 'max:'.$max],
            'apkArm32' => ['nullable', 'file', 'max:'.$max],
            'apkUniversal' => ['nullable', 'file', 'max:'.$max],
            // Se leen del propio APK (docs/09 §33); solo hacen falta si no se puede leer.
            'versionName' => ['nullable', 'string', 'max:20'],
            'versionCode' => ['nullable', 'integer', 'min:1'],
            'notes' => ['nullable', 'string', 'max:5000'],
            'mandatory' => ['nullable', 'in:0,1,true,false'],
        ]);

        $files = [];

        foreach (self::FILE_FIELDS as $field => $abi) {
            if (! $request->hasFile($field)) {
                continue;
            }

            $file = $request->file($field);

            if (strtolower($file->getClientOriginalExtension()) !== 'apk' || file_get_contents($file->getRealPath(), false, null, 0, 2) !== 'PK') {
                throw new JsonApiException(422, 'APK_INVALID', 'Archivo no válido', 'El archivo debe ser un APK de Android.', ['pointer' => '/'.$field]);
            }

            $files[$abi] = $file;
        }

        if ($files === []) {
            throw new JsonApiException(422, 'APK_REQUIRED', 'Falta el APK', 'Suba al menos un APK (64 bits, 32 bits o universal).', ['pointer' => '/apkArm64']);
        }

        $name = $request->input('versionName');
        $code = $request->input('versionCode') !== null ? (int) $request->input('versionCode') : null;

        foreach ($files as $abi => $file) {
            $info = ApkInfo::read($file->getRealPath());
            $field = array_search($abi, self::FILE_FIELDS, true);

            if (! $info || ! $info['versionCode']) {
                continue;
            }
            if ($code !== null && $code !== (int) $info['versionCode'] || $name !== null && $info['versionName'] !== null && trim($name) !== $info['versionName']) {
                throw new JsonApiException(422, 'APK_VERSION_MISMATCH', 'Versiones distintas',
                    'Los APK deben ser de la misma versión (este es la '.$info['versionName'].', código '.$info['versionCode'].').', ['pointer' => '/'.$field]);
            }
            $code = (int) $info['versionCode'];
            $name = $info['versionName'] ?: $name;
        }

        if ($code === null || $name === null || trim($name) === '') {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Falta la versión',
                'No se pudo leer la versión del APK; escríbala a mano.', ['pointer' => '/versionName']);
        }

        $latest = AppVersion::max('version_code');

        if ($latest !== null && $code <= $latest) {
            throw new JsonApiException(422, 'VERSION_CODE_TOO_LOW', 'Versión no válida',
                "El versionCode debe ser mayor que el de la última versión publicada ({$latest}).", ['pointer' => '/versionCode']);
        }

        $version = DB::transaction(function () use ($request, $uploads, $files, $code, $name) {
            $version = AppVersion::create([
                'version_name' => trim($name),
                'version_code' => $code,
                'notes' => $request->input('notes'),
                'mandatory' => in_array($request->input('mandatory'), ['1', 'true', 1, true], true),
                'published_by' => $request->user()->id,
            ]);

            foreach ($files as $abi => $file) {
                AppVersionFile::create([
                    'app_version_id' => $version->id,
                    'abi' => $abi,
                    'sha256' => hash_file('sha256', $file->getRealPath()),
                    'size_bytes' => $file->getSize(),
                    'apk_path' => $uploads->store($file, 'apk', 'apk'),
                ]);
            }

            return $version;
        });

        return JsonApiResponse::make((new Document($request))->resource($version->fresh()), 201);
    }

    /**
     * Cambiar las novedades o si es obligatoria (attributes.notes, attributes.mandatory).
     */
    public function update(Request $request, $id)
    {
        $this->ensureAdmin($request);
        $version = AppVersion::findOrFail($id);
        $data = $this->validateResource($request, 'app-versions', [
            'attributes.mandatory' => ['sometimes', 'boolean'],
            'attributes.notes' => ['sometimes', 'nullable', 'string', 'max:5000'],
        ]);

        foreach (['mandatory' => 'mandatory', 'notes' => 'notes'] as $attribute => $column) {
            if (array_key_exists($attribute, $data['attributes'] ?? [])) {
                $version->{$column} = $data['attributes'][$attribute];
            }
        }

        $version->save();

        return JsonApiResponse::make((new Document($request))->resource($version->fresh()));
    }

    /**
     * Retirar una versión (deja de ofrecerse y se borra el archivo).
     */
    public function destroy(Request $request, Uploads $uploads, $id)
    {
        $this->ensureAdmin($request);
        $version = AppVersion::findOrFail($id);

        foreach ($version->files as $file) {
            $uploads->delete($file->apk_path);
            $file->delete();
        }

        $version->delete();

        return response('', 204);
    }

    private function ensureAdmin(Request $request): void
    {
        app(\App\Services\Access::class)->requireAdmin($request->user(), 'Solo el Administrador publica y retira versiones de la app.');
    }
}
