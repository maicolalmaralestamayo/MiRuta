<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Entity extends Model
{
    protected $fillable = ['abbreviation', 'number', 'name', 'description', 'observation', 'image_path', 'active'];

    protected $casts = ['active' => 'boolean'];

    public static function findByAbbreviation(string $abbreviation): ?self
    {
        return static::where('abbreviation', mb_strtoupper(trim($abbreviation)))->first();
    }

    public function itineraries()
    {
        return $this->hasMany(Itinerary::class);
    }
}
