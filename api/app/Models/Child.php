<?php

namespace App\Models;

use App\Support\IdentityCard;
use Illuminate\Database\Eloquent\Model;

/**
 * Hijo de una o varias personas (docs/11 §11.11).
 */
class Child extends Model
{
    protected $fillable = [
        'identity_card_encrypted', 'identity_card_hash', 'first_name', 'middle_name', 'first_surname', 'second_surname',
        'sex', 'birth_date', 'photo_path', 'active',
    ];

    protected $hidden = ['identity_card_encrypted', 'identity_card_hash'];

    protected $casts = ['active' => 'boolean', 'birth_date' => 'date'];

    public static function findByIdentityCard(string $card): ?self
    {
        return static::where('identity_card_hash', IdentityCard::hash($card))->first();
    }

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

    public function identityCard(): ?string
    {
        return IdentityCard::decrypt($this->identity_card_encrypted);
    }
}
