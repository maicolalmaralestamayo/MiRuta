<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SettingDefinition extends Model
{
    use SoftDeletes;

    const TYPE_INTEGER = 'integer';
    const TYPE_BOOLEAN = 'boolean';
    const TYPE_STRING = 'string';
    const TYPE_TIME = 'time';
    const TYPE_OPTION = 'option';

    protected $fillable = [
        'key', 'name', 'description', 'observation', 'value_type', 'default_value',
        'min_value', 'max_value', 'min_setting_definition_id', 'editable_by', 'user_overridable',
    ];

    protected $casts = [
        'min_value' => 'integer',
        'max_value' => 'integer',
        'user_overridable' => 'boolean',
    ];

    public function options()
    {
        return $this->hasMany(SettingOption::class);
    }

    /**
     * Ajuste global que fija el valor mínimo de este (p. ej. min_background_poll_minutes).
     */
    public function minSettingDefinition()
    {
        return $this->belongsTo(self::class, 'min_setting_definition_id');
    }
}
