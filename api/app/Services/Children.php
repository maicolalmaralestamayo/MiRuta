<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Child;
use App\Models\ChildParent;
use App\Models\User;
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
     * Añade (o vincula) un hijo a la persona. Sin carné (docs/11 §11.67): el
     * mismo niño declarado por otra persona es el de iguales nombres,
     * apellidos y fecha de nacimiento.
     *
     * @param array $data [first_name, middle_name, first_surname, second_surname, sex, birth_date]
     * @return array{0: Child, 1: bool} [hijo, ya lo tenía declarado otra persona]
     */
    public function add(User $parent, array $data): array
    {
        $existing = $this->findSame($data);

        if ($existing && ChildParent::where('child_id', $existing->id)->where('user_id', $parent->id)->exists()) {
            throw JsonApiException::conflict('CHILD_ALREADY_DECLARED', 'Ya tiene declarado a ese hijo.', '/data/attributes/firstName');
        }

        $this->ensureEligible($data['birth_date']);

        return DB::transaction(function () use ($parent, $data, $existing) {
            $child = $existing;
            $declared = $existing !== null;

            if (! $child) {
                $child = new Child();
                $child->forceFill($data + ['sex' => 'M', 'active' => true])->save();
            }

            ChildParent::firstOrCreate(['child_id' => $child->id, 'user_id' => $parent->id]);

            return [$child->fresh(), $declared];
        });
    }

    /** Un niño ya registrado con los mismos nombres, apellidos y fecha de nacimiento. */
    public function findSame(array $data, ?int $except = null): ?Child
    {
        $normalize = fn ($v) => mb_strtolower(trim((string) $v));

        return Child::whereDate('birth_date', $data['birth_date'])
            ->when($except !== null, fn ($q) => $q->where('id', '<>', $except))
            ->get()
            ->first(fn (Child $c) => $normalize($c->first_name) === $normalize($data['first_name'] ?? '')
                && $normalize($c->middle_name) === $normalize($data['middle_name'] ?? '')
                && $normalize($c->first_surname) === $normalize($data['first_surname'] ?? '')
                && $normalize($c->second_surname) === $normalize($data['second_surname'] ?? ''));
    }

    public function update(Child $child, array $data, ?bool $active): Child
    {
        DB::transaction(function () use ($child, $data, $active) {
            if (isset($data['birth_date']) && (string) $data['birth_date'] !== $child->birth_date?->toDateString()) {
                $this->ensureEligible($data['birth_date'], '/data/attributes/birthDate');
            }

            $child->fill($data);

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

    private function ensureEligible($birthDate, string $pointer = '/data/attributes/birthDate'): void
    {
        if (! $this->eligibility->isEligible($birthDate)) {
            throw new JsonApiException(422, 'CHILD_NOT_ELIGIBLE', 'Sin derecho a viajar',
                'El niño ya no tiene derecho a viajar: lo tuvo hasta el '.SpanishDate::date($this->eligibility->eligibleUntil($birthDate)).'.',
                ['pointer' => $pointer]);
        }
    }
}
