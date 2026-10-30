<?php

namespace App\Serializers;

use App\Models\Worker;
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
            'downloadUrl' => url($version->apk_path),
            'sizeBytes' => $version->size_bytes,
            'sha256' => $version->sha256,
            'publishedAt' => $this->date($version->created_at),
        ];
    }

    public function meta(Model $version, Request $request): array
    {
        $viewer = $request->user();

        // Cuántos trabajadores la tienen instalada (solo para el Administrador).
        return $viewer && $viewer->isAdmin()
            ? ['installedCount' => Worker::where('app_version_code', $version->version_code)->count()]
            : [];
    }
}
