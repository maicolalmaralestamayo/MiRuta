<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * APK de una versión para un tipo de procesador.
 */
class AppVersionFile extends Model
{

    const ABI_ARM64 = 'arm64-v8a';
    const ABI_ARM32 = 'armeabi-v7a';
    const ABI_UNIVERSAL = 'universal';
    const ABIS = [self::ABI_ARM64, self::ABI_ARM32, self::ABI_UNIVERSAL];

    protected $fillable = ['app_version_id', 'abi', 'apk_path', 'size_bytes', 'sha256'];

    protected $casts = ['size_bytes' => 'integer'];

    public function appVersion()
    {
        return $this->belongsTo(AppVersion::class);
    }
}
