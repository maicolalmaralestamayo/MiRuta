<?php

namespace App\Models;

use App\Support\IdentityCard;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * Hijo (docs/11 §11.11): es de la persona, se identifica por su carné y lo
 * pueden tener declarado varios padres (child_parents).
 */
class Child extends Model
{
    use SoftDeletes;

    protected $table = 'children';

    protected $fillable = [
        'identity_card_encrypted', 'identity_card_hash', 'first_name', 'middle_name', 'first_surname', 'second_surname',
        'sex', 'birth_date', 'photo_path', 'active',
    ];

    protected $hidden = ['identity_card_encrypted', 'identity_card_hash'];

    protected $casts = [
        'active' => 'boolean',
        'birth_date' => 'date',
    ];

    public function parentLinks()
    {
        return $this->hasMany(ChildParent::class);
    }

    /**
     * Padres y madres que lo tienen declarado.
     */
    public function parents()
    {
        return $this->belongsToMany(User::class, 'child_parents')->wherePivotNull('deleted_at')->withTimestamps();
    }

    /**
     * Los que tiene declarados esa persona.
     */
    public function scopeOfParent(Builder $query, int $userId): Builder
    {
        return $query->whereIn('children.id', ChildParent::where('user_id', $userId)->select('child_id'));
    }

    /**
     * @return int[]
     */
    public function parentIds(): array
    {
        return array_map('intval', ChildParent::where('child_id', $this->id)->pluck('user_id')->all());
    }

    public function identityCard(): ?string
    {
        return IdentityCard::decrypt($this->identity_card_encrypted);
    }

    public static function findByIdentityCard(string $card, bool $withTrashed = false): ?self
    {
        $query = $withTrashed ? static::withTrashed() : static::query();

        return $query->where('identity_card_hash', IdentityCard::hash($card))->first();
    }

    public function fullName(): string
    {
        return implode(' ', array_filter([$this->first_name, $this->middle_name, $this->first_surname, $this->second_surname], 'strlen'));
    }
}
