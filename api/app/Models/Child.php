<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * Hijo de una o varias personas (docs/11 §11.11).
 */
class Child extends Model
{
    use \App\Models\Concerns\LogsChanges;

    protected $fillable = [
        'first_name', 'middle_name', 'first_surname', 'second_surname',
        'sex', 'birth_date', 'photo_path', 'active',
    ];


    protected $casts = ['active' => 'boolean', 'birth_date' => 'date'];


    public function scopeOfParent($query, int $userId)
    {
        return $query->whereIn('id', ChildParent::where('user_id', $userId)->select('child_id'));
    }

    public function fullName(): string
    {
        return implode(' ', array_filter([$this->first_name, $this->middle_name, $this->first_surname, $this->second_surname], 'strlen'));
    }

    /** @return int[] */
    public function parentIds(): array
    {
        return array_map('intval', ChildParent::where('child_id', $this->id)->pluck('user_id')->all());
    }
}
