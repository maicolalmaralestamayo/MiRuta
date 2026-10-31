<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

class UserSetting extends Model
{
    use SoftDeletes;

    protected $fillable = ['user_id', 'setting_definition_id', 'value'];

    public function definition()
    {
        return $this->belongsTo(SettingDefinition::class, 'setting_definition_id');
    }

    public function user()
    {
        return $this->belongsTo(User::class);
    }
}
