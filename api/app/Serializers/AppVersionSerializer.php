<?php

namespace App\Serializers;

use App\Models\AppVersionFile;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

class AppVersionSerializer extends Serializer
{
    public function type(): string
    {
        return 'app-versions';
    }

    public function attributes(Model $version, Request $request): array
    {
        return [
            'versionName' => $version->version_name,
            'versionCode' => $version->version_code,
            'notes' => $version->notes,
            'mandatory' => $version->mandatory,
            'files' => $version->files->sortBy('abi')->values()->map(function (AppVersionFile $file) {
                return [
                    'abi' => $file->abi,
                    'downloadUrl' => url($file->apk_path),
                    'sizeBytes' => $file->size_bytes,
                    'sha256' => $file->sha256,
                ];
            })->all(),
            'publishedAt' => $this->date($version->created_at),
        ];
    }

    public function meta(Model $version, Request $request): array
    {
        $viewer = $request->user();

        // Cuántas cuentas la tienen instalada (solo para el Administrador).
        return $viewer && $viewer->isAdmin()
            ? ['installedCount' => User::where('app_version_code', $version->version_code)->count()]
            : [];
    }
}
