<?php

namespace App\Serializers;

use App\Models\ChildParent;
use App\Models\User;
use App\Services\ChildEligibility;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Hijo (docs/11 §11.11). El carné y quién más lo tiene declarado los ven
 * sus padres y el Administrador.
 */
class ChildSerializer extends Serializer
{
    public function type(): string
    {
        return 'children';
    }

    public function attributes(Model $child, Request $request): array
    {
        $eligibility = app(ChildEligibility::class);
        $attributes = [
            'firstName' => $child->first_name,
            'middleName' => $child->middle_name,
            'firstSurname' => $child->first_surname,
            'secondSurname' => $child->second_surname,
            'fullName' => $child->fullName(),
            'sex' => $child->sex,
            'birthDate' => $this->day($child->birth_date),
            'eligibleUntil' => $eligibility->eligibleUntil($child->birth_date)->toDateString(),
            'eligible' => $eligibility->isEligible($child->birth_date),
            'active' => (bool) $child->active,
            'photoUrl' => $this->image($child->photo_path),
        ];

        if (self::canSeePrivateData($child, $request)) {
            $attributes['identityCard'] = $child->identityCard();
        }

        return $attributes;
    }

    public function meta(Model $child, Request $request): array
    {
        if (! self::canSeePrivateData($child, $request)) {
            return [];
        }

        $parents = User::whereIn('id', ChildParent::where('child_id', $child->id)->select('user_id'))->get();

        return [
            'parents' => $parents->map(fn (User $parent) => ['id' => (string) $parent->id, 'fullName' => $parent->fullName()])->values()->all(),
        ];
    }

    public static function canSeePrivateData(Model $child, Request $request): bool
    {
        $viewer = $request->user();

        return $viewer && ($viewer->isAdmin() || ChildParent::where('child_id', $child->id)->where('user_id', $viewer->id)->exists());
    }
}
