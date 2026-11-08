<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Versión de la app publicada por el Administrador.
 */
class AppVersion extends Model
{

    protected $fillable = ['version_name', 'version_code', 'notes', 'mandatory', 'published_by'];

    protected $casts = [
        'version_code' => 'integer',
        'mandatory' => 'boolean',
    ];

    public function publisher()
    {
        return $this->belongsTo(User::class, 'published_by');
    }

    public function files()
    {
        return $this->hasMany(AppVersionFile::class);
    }

    /**
     * APK para ese tipo de procesador: el suyo, si no el universal, si no
     * (versión con un solo APK) el único que haya.
     *
     * @param string[] $supportedAbis ABI que admite el teléfono, por preferencia
     */
    public function fileFor(array $supportedAbis): ?AppVersionFile
    {
        $files = $this->files->keyBy('abi');

        foreach (array_merge($supportedAbis, [AppVersionFile::ABI_UNIVERSAL]) as $abi) {
            if (isset($files[$abi])) {
                return $files[$abi];
            }
        }

        return $files->count() === 1 ? $files->first() : null;
    }

    public static function latest(): ?self
    {
        return static::orderBy('version_code', 'desc')->first();
    }

    /**
     * Hay una versión obligatoria posterior a la indicada.
     */
    public static function isMandatoryAfter(int $versionCode): bool
    {
        return static::where('version_code', '>', $versionCode)->where('mandatory', true)->exists();
    }
}
