<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Child;
use App\Models\ChildParent;
use App\Models\User;
use App\Support\IdentityCard;
use App\Support\SpanishDate;
use Illuminate\Support\Facades\DB;

/**
 * Hijos (docs/11 §11.11): los padres los añaden, corrigen y quitan
 * directamente. Un mismo niño puede tenerlo declarado más de una persona.
 */
class Children
{
    public function __construct(private ChildEligibility $eligibility)
    {
    }

    /**
     * Añade (o vincula) un hijo a la persona.
     *
     * @return array{0: Child, 1: bool} [hijo, ya lo tenía declarado otra persona]
     */
    public function add(User $parent, array $names, string $identityCard): array
    {
        $card = IdentityCard::validated($identityCard);
        $existing = Child::findByIdentityCard($card);

        if ($existing && ChildParent::where('child_id', $existing->id)->where('user_id', $parent->id)->exists()) {
            throw JsonApiException::conflict('CHILD_ALREADY_DECLARED', 'Ya tiene declarado a ese hijo.', '/data/attributes/identityCard');
        }

        $this->ensureEligible(IdentityCard::birthDate($card));

        return DB::transaction(function () use ($parent, $names, $card, $existing) {
            $child = $existing;
            $declared = $existing !== null;

            if (! $child) {
                $child = new Child();
                $child->forceFill($names + IdentityCard::columns($card) + ['active' => true])->save();
            }

            ChildParent::firstOrCreate(['child_id' => $child->id, 'user_id' => $parent->id]);

            return [$child->fresh(), $declared];
        });
    }

    public function update(Child $child, array $names, ?string $identityCard, ?bool $active): Child
    {
        DB::transaction(function () use ($child, $names, $identityCard, $active) {
            if ($identityCard !== null) {
                $card = IdentityCard::validated($identityCard);

                if (IdentityCard::hash($card) !== $child->identity_card_hash) {
                    $other = Child::findByIdentityCard($card);

                    if ($other && (int) $other->id !== (int) $child->id) {
                        throw JsonApiException::conflict('IDENTITY_CARD_TAKEN', 'Ya hay otro niño registrado con ese carné de identidad.', '/data/attributes/identityCard');
                    }

                    $this->ensureEligible(IdentityCard::birthDate($card));
                    $child->forceFill(IdentityCard::columns($card));
                }
            }

            $child->fill($names);

            if ($active !== null) {
                if ($active && ! $child->active) {
                    $this->ensureEligible($child->birth_date, '/data/attributes/active');
                }

                $child->active = $active;
            }

            $child->save();
        });

        return $child->fresh();
    }

    /**
     * Eliminar = desvincular del padre; si no le quedan padres, se borra.
     */
    public function unlink(Child $child, int $parentId): void
    {
        DB::transaction(function () use ($child, $parentId) {
            ChildParent::where('child_id', $child->id)->where('user_id', $parentId)->delete();

            if (! ChildParent::where('child_id', $child->id)->exists()) {
                $child->delete();
            }
        });
    }

    public function isParent(Child $child, User $user): bool
    {
        return ChildParent::where('child_id', $child->id)->where('user_id', $user->id)->exists();
    }

    private function ensureEligible($birthDate, string $pointer = '/data/attributes/identityCard'): void
    {
        if (! $this->eligibility->isEligible($birthDate)) {
            throw new JsonApiException(422, 'CHILD_NOT_ELIGIBLE', 'Sin derecho a viajar',
                'El niño ya no tiene derecho a viajar: lo tuvo hasta el '.SpanishDate::date($this->eligibility->eligibleUntil($birthDate)).'.',
                ['pointer' => $pointer]);
        }
    }
}
