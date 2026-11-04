<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Entidad: empresa que usa la app. Se muestra por su abreviatura.
 */
class Entity extends Model
{
    use SoftDeletes;

    protected $fillable = ['abbreviation', 'number', 'name', 'description', 'observation', 'image_path'];

    public static function normalizeAbbreviation($value): string
    {
        return is_string($value) ? mb_strtoupper(trim($value), 'UTF-8') : '';
    }

    public static function findByAbbreviation($value): ?self
    {
        $abbreviation = self::normalizeAbbreviation($value);

        return $abbreviation === '' ? null : static::where('abbreviation', $abbreviation)->first();
    }

    public function workers()
    {
        return $this->hasMany(Worker::class);
    }
}
