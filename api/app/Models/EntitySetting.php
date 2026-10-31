<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Valor de un ajuste de nivel Entidad para una Entidad concreta.
 */
class EntitySetting extends Model
{
    use SoftDeletes;

    protected $fillable = ['entity_id', 'setting_definition_id', 'value'];

    public function definition()
    {
        return $this->belongsTo(SettingDefinition::class, 'setting_definition_id');
    }

    public function entity()
    {
        return $this->belongsTo(Entity::class);
    }
}
