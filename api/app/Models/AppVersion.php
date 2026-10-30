<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Versión de la app publicada por el Administrador.
 */
class AppVersion extends Model
{
    use SoftDeletes;

    protected $fillable = ['version_name', 'version_code', 'notes', 'mandatory', 'apk_path', 'size_bytes', 'sha256', 'published_by'];

    protected $casts = [
        'version_code' => 'integer',
        'mandatory' => 'boolean',
        'size_bytes' => 'integer',
    ];

    public function publisher()
    {
        return $this->belongsTo(Worker::class, 'published_by')->withTrashed();
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
