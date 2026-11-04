<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Child;
use App\Models\ChildParent;
use App\Models\User;
use App\Support\IdentityCard;
use Illuminate\Support\Facades\DB;

/**
 * Hijos sin solicitudes (docs/11 §11.11): los padres los añaden, corrigen,
 * desactivan y quitan directamente. Un niño puede tenerlo declarado más de
 * una persona: si ya existe, se le vincula al nuevo padre con aviso.
 */
class Children
{
    /** @var ChildEligibility */
    private $eligibility;

    public function __construct(ChildEligibility $eligibility)
    {
        $this->eligibility = $eligibility;
    }

    /**
     * Añade (o vincula) un hijo a la persona.
     *
     * @return array [Child, bool ya estaba declarado por otra persona]
     */
    public function add(User $parent, array $names, string $identityCard): array
    {
        $card = IdentityCard::validated($identityCard);
        $existing = Child::findByIdentityCard($card, true);

        if ($existing && ChildParent::where('child_id', $existing->id)->where('user_id', $parent->id)->exists()) {
            throw JsonApiException::conflict('CHILD_ALREADY_DECLARED', 'Ya tiene declarado a ese hijo.', '/data/attributes/identityCard');
        }

        $otherParents = $existing ? $existing->parentIds() : [];
        $entityId = $this->eligibility->entityForParents(array_merge($otherParents, [(int) $parent->id]));
        $this->ensureEligible(IdentityCard::birthDate($card), $entityId);

        return DB::transaction(function () use ($parent, $names, $card, $existing, $otherParents) {
            if ($existing) {
                $child = $existing;

                if ($child->trashed()) {
                    // Sin padres se había borrado: vuelve con los datos nuevos.
                    $child->forceFill($names + ['deleted_at' => null, 'active' => true])->save();
                }
            } else {
                $child = new Child();
                $child->forceFill($names + IdentityCard::columns($card) + ['active' => true])->save();
            }

            $this->link($child, (int) $parent->id);

            return [$child->fresh(), $otherParents !== []];
        });
    }

    /**
     * Corrige nombres, carné o estado.
     */
    public function update(Child $child, array $names, ?string $identityCard, ?bool $active): Child
    {
        DB::transaction(function () use ($child, $names, $identityCard, $active) {
            if ($identityCard !== null) {
                $card = IdentityCard::validated($identityCard);

                if (IdentityCard::hash($card) !== $child->identity_card_hash) {
                    $other = Child::findByIdentityCard($card, true);

                    if ($other && (int) $other->id !== (int) $child->id) {
                        throw JsonApiException::conflict('IDENTITY_CARD_TAKEN', 'Ya hay otro niño registrado con ese carné de identidad.', '/data/attributes/identityCard');
                    }

                    $this->ensureEligible(IdentityCard::birthDate($card), $this->eligibility->childEntityId($child), '/data/attributes/identityCard');
                    $child->forceFill(IdentityCard::columns($card));
                }
            }

            $child->fill($names);

            if ($active !== null) {
                if ($active && ! $child->active) {
                    $this->ensureEligible($child->birth_date, $this->eligibility->childEntityId($child), '/data/attributes/active');
                }

                $child->active = $active;
            }

            $child->save();
        });

        return $child->fresh();
    }

    /**
     * Eliminar = desvincular del padre; si no le quedan padres, borrado lógico.
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

    private function link(Child $child, int $parentId): void
    {
        $link = ChildParent::withTrashed()->firstOrNew(['child_id' => $child->id, 'user_id' => $parentId]);
        $link->deleted_at = null;
        $link->save();
    }

    private function ensureEligible($birthDate, ?int $entityId, string $pointer = '/data/attributes/identityCard'): void
    {
        if (! $this->eligibility->isEligible($birthDate, $entityId)) {
            throw new JsonApiException(422, 'CHILD_NOT_ELIGIBLE', 'Sin derecho a viajar',
                'El niño ya no tiene derecho a viajar: lo tuvo hasta el '.\App\Support\SpanishDate::date($this->eligibility->eligibleUntil($birthDate, $entityId)).'.',
                ['pointer' => $pointer]);
        }
    }
}
