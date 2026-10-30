<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class SettingOption extends Model
{
    use SoftDeletes;

    protected $fillable = ['setting_definition_id', 'value', 'name'];

    public function definition()
    {
        return $this->belongsTo(SettingDefinition::class, 'setting_definition_id');
    }
}
