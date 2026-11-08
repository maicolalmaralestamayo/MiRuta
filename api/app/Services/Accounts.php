<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Entity;
use App\Models\ReleasedUsername;
use App\Models\User;
use App\Models\Worker;
use App\Support\IdentityCard;
use App\Support\Username;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Personas: registro, registro por el Administrador, usuario y carné
 * (docs/11 §11.2, §11.4 y §11.5).
 */
class Accounts
{
    /**
     * Intentos de la transacción: si dos registros simultáneos en un sistema
     * sin Administrador chocan, se reintenta y el segundo ya no lo será.
     */
    const TRANSACTION_ATTEMPTS = 3;

    /** Texto exacto de docs/11 §11.5. */
    const IDENTITY_CARD_TAKEN = 'Alguien ya se registró con este carné de identidad. Si fue usted, emplee la opción Olvidé algo. '
        .'Si no fue usted, comuníquese con el Administrador de la aplicación o con su Jefe de itinerario.';

    public function __construct(private Passwords $passwords, private Memberships $memberships)
    {
    }

    /**
     * Registro de la propia persona, sin Entidad. Si aún no hay
     * Administrador, quien se registra lo es (comprobado con bloqueo).
     *
     * @param array $names [first_name, middle_name, first_surname, second_surname]
     */
    public function register(array $names, string $identityCard, string $username, string $password): User
    {
        $card = IdentityCard::validated($identityCard);
        $this->ensureIdentityCardFree($card);
        $username = $this->ensureUsernameAvailable($username);
        $this->passwords->validate($password, array_merge([$username], array_values($names)));

        return DB::transaction(function () use ($names, $card, $username, $password) {
            $adminExists = User::where('is_admin', true)->lockForUpdate()->exists();
            $user = new User();
            $user->forceFill($names + IdentityCard::columns($card) + [
                'username' => $username,
                'password' => '',
                'is_admin' => ! $adminExists,
            ])->save();
            $this->passwords->set($user, $password);

            return $user;
        }, self::TRANSACTION_ATTEMPTS);
    }

    public static function adminExists(): bool
    {
        return User::where('is_admin', true)->exists();
    }

    /**
     * El Administrador registra a una persona en una
     * Entidad. Si el carné ya existe no se crea otra cuenta: se le añade la
     * Entidad, ya aprobada. Usuario y contraseña se proponen si faltan; la
     * contraseña hay que cambiarla al entrar.
     *
     * @return array ['worker' => Worker, 'created' => bool, 'username' => ?string, 'password' => ?string]
     */
    public function registerByAdmin(Entity $entity, array $names, string $identityCard, ?string $username, ?string $password): array
    {
        $card = IdentityCard::validated($identityCard);
        $existing = User::findByIdentityCard($card);

        if ($existing) {
            if (Worker::where('user_id', $existing->id)->where('entity_id', $entity->id)->exists()) {
                throw JsonApiException::conflict('ALREADY_MEMBER', 'Esa persona ya pertenece a la Entidad.', '/data/attributes/identityCard');
            }

            $worker = $this->memberships->join($existing, $entity);

            return ['worker' => $worker, 'created' => false, 'username' => null, 'password' => null];
        }

        $username = $username !== null && trim($username) !== ''
            ? $this->ensureUsernameAvailable($username)
            : Username::suggest($names['first_name'] ?? null, $names['middle_name'] ?? null, $names['first_surname'] ?? null, $names['second_surname'] ?? null);
        $password = $password !== null && $password !== '' ? $password : $this->passwords->suggest();
        $this->passwords->validate($password, array_merge([$username], array_values($names)));

        return DB::transaction(function () use ($entity, $names, $card, $username, $password) {
            $user = new User();
            $user->forceFill($names + IdentityCard::columns($card) + [
                'username' => $username,
                'password' => '',
                'is_admin' => false,
            ])->save();
            $this->passwords->set($user, $password);
            // Contraseña puesta por otro: hay que cambiarla al entrar (docs/11 §11.7).
            $user->forceFill(['must_change_password' => true])->save();
            $worker = $this->memberships->join($user, $entity);

            return ['worker' => $worker, 'created' => true, 'username' => $username, 'password' => $password];
        });
    }

    /**
     * El carné no lo tiene ya otra persona (409 IDENTITY_CARD_TAKEN).
     */
    public function ensureIdentityCardFree(string $card, ?User $except = null, string $pointer = '/data/attributes/identityCard'): void
    {
        $other = User::findByIdentityCard($card);

        if ($other && (! $except || (int) $other->id !== (int) $except->id)) {
            throw JsonApiException::conflict('IDENTITY_CARD_TAKEN', self::IDENTITY_CARD_TAKEN, $pointer);
        }
    }

    /**
     * Cambia el carné (y con él el sexo y la fecha de nacimiento).
     */
    public function changeIdentityCard(User $user, $identityCard, string $pointer = '/data/attributes/identityCard'): void
    {
        $card = IdentityCard::validated($identityCard, $pointer);

        if (IdentityCard::hash($card) === $user->identity_card_hash) {
            return;
        }

        $this->ensureIdentityCardFree($card, $user, $pointer);
        $user->forceFill(IdentityCard::columns($card))->save();
    }

    /**
     * Comprueba que el usuario se pueda usar y lo devuelve normalizado.
     */
    public function ensureUsernameAvailable(string $username, ?User $user = null, string $pointer = '/data/attributes/username'): string
    {
        if ($reason = Username::unavailableReason($username)) {
            throw new JsonApiException(422, 'USERNAME_INVALID', 'Usuario no válido', $reason, ['pointer' => $pointer]);
        }

        $username = Username::normalize($username);

        if (Username::taken($username, $user ? $user->id : null)) {
            throw JsonApiException::conflict('USERNAME_TAKEN', 'Ese usuario ya existe o se dejó de usar hace poco. Elija otro.', $pointer);
        }

        return $username;
    }

    public function changeUsername(User $user, string $username): void
    {
        $username = $this->ensureUsernameAvailable($username, $user);

        if ($username === $user->username) {
            return;
        }

        if ($user->username !== null) {
            ReleasedUsername::create(['user_id' => $user->id, 'username' => $user->username, 'released_at' => Carbon::now()]);
        }

        $user->username = $username;
        $user->save();
    }

    public function entityOrFail(string $abbreviation, string $pointer = '/data/attributes/entityAbbreviation'): Entity
    {
        $entity = Entity::findByAbbreviation($abbreviation);

        if (! $entity) {
            throw new JsonApiException(422, 'ENTITY_NOT_FOUND', 'Entidad no encontrada',
                'No hay ninguna Entidad con esa abreviatura. Pregúntela a su superior.', ['pointer' => $pointer]);
        }

        return $entity;
    }
}
