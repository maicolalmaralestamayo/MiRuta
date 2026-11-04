<?php

namespace App\Serializers;

use App\Models\ChildParent;
use App\Models\User;
use App\Services\ChildEligibility;
use App\Services\Permissions;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Hijo (docs/11 §11.11). El carné y quién más lo tiene declarado los ven
 * sus padres y quien gestiona los hijos de todos (children.manage «all»).
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
            'birthDate' => $child->birth_date ? $child->birth_date->toDateString() : null,
            'eligibleUntil' => $eligibility->childEligibleUntil($child)->toDateString(),
            'eligible' => $eligibility->isChildEligible($child),
            'active' => (bool) $child->active,
            'photoUrl' => $child->photo_path ? url($child->photo_path) : null,
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

        // Quién lo tiene declarado (en el formulario del hijo).
        $parents = User::withTrashed()->whereIn('id', ChildParent::where('child_id', $child->id)->select('user_id'))->get();

        return [
            'parents' => $parents->map(function (User $parent) {
                return ['id' => (string) $parent->id, 'fullName' => $parent->fullName()];
            })->values()->all(),
        ];
    }

    public static function canSeePrivateData(Model $child, Request $request): bool
    {
        $viewer = $request->user();

        if (! $viewer) {
            return false;
        }

        return ChildParent::where('child_id', $child->id)->where('user_id', $viewer->id)->exists()
            || app(Permissions::class)->can($viewer, 'children.manage');
    }
}
