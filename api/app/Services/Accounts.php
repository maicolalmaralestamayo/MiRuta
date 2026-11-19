<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Entity;
use App\Models\ReleasedUsername;
use App\Models\User;
use App\Models\Worker;
use App\Support\Email;
use App\Support\Username;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Personas: registro, registro por el Administrador, usuario y correo
 * electrónico (docs/11 §11.2, §11.4, §11.5 y §11.67: el correo sustituye al
 * carné de identidad y es único en toda la base de datos).
 */
class Accounts
{
    /**
     * Intentos de la transacción: si dos registros simultáneos en un sistema
     * sin Administrador chocan, se reintenta y el segundo ya no lo será.
     */
    const TRANSACTION_ATTEMPTS = 3;

    /** Texto de docs/11 §11.5, con el correo en lugar del carné (§11.67). */
    const EMAIL_TAKEN = 'Alguien ya se registró con este correo electrónico. Si fue usted, emplee la opción Olvidé algo. '
        .'Si no fue usted, comuníquese con el Administrador de la aplicación o con su Jefe de itinerario.';

    public function __construct(private Passwords $passwords, private Memberships $memberships)
    {
    }

    /**
     * Registro de la propia persona, sin Entidad. Si aún no hay
     * Administrador, quien se registra lo es (comprobado con bloqueo).
     *
     * @param array $names [first_name, middle_name, first_surname, second_surname, sex?, birth_date?]
     */
    public function register(array $names, string $email, string $username, string $password): User
    {
        $email = Email::validated($email);
        $this->ensureEmailFree($email);
        $username = $this->ensureUsernameAvailable($username);
        $this->passwords->validate($password, array_merge([$username], self::passwordWords($names)));

        return DB::transaction(function () use ($names, $email, $username, $password) {
            $adminExists = User::where('is_admin', true)->lockForUpdate()->exists();
            $user = new User();
            $user->forceFill($names + ['email' => $email, 'sex' => 'M'] + [
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
     * Entidad. Si el correo ya existe no se crea otra cuenta: se le añade la
     * Entidad, ya aprobada. Usuario y contraseña se proponen si faltan; la
     * contraseña hay que cambiarla al entrar.
     *
     * @return array ['worker' => Worker, 'created' => bool, 'username' => ?string, 'password' => ?string]
     */
    public function registerByAdmin(Entity $entity, array $names, string $email, ?string $username, ?string $password): array
    {
        $email = Email::validated($email);
        $existing = User::findByEmail($email);

        if ($existing) {
            if (Worker::where('user_id', $existing->id)->where('entity_id', $entity->id)->exists()) {
                throw JsonApiException::conflict('ALREADY_MEMBER', 'Esa persona ya pertenece a la Entidad.', '/data/attributes/email');
            }

            $worker = $this->memberships->join($existing, $entity);

            return ['worker' => $worker, 'created' => false, 'username' => null, 'password' => null];
        }

        $username = $username !== null && trim($username) !== ''
            ? $this->ensureUsernameAvailable($username)
            : Username::suggest($names['first_name'] ?? null, $names['middle_name'] ?? null, $names['first_surname'] ?? null, $names['second_surname'] ?? null);
        $password = $password !== null && $password !== '' ? $password : $this->passwords->suggest();
        $this->passwords->validate($password, array_merge([$username], self::passwordWords($names)));

        return DB::transaction(function () use ($entity, $names, $email, $username, $password) {
            $user = new User();
            $user->forceFill($names + ['email' => $email, 'sex' => 'M'] + [
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

    /** Palabras que la contraseña no puede contener (nombres y apellidos). */
    private static function passwordWords(array $names): array
    {
        return array_values(array_intersect_key($names, array_flip(['first_name', 'middle_name', 'first_surname', 'second_surname'])));
    }

    /**
     * El correo no lo tiene ya otra persona (409 EMAIL_TAKEN).
     */
    public function ensureEmailFree(string $email, ?User $except = null, string $pointer = '/data/attributes/email'): void
    {
        $other = User::findByEmail($email);

        if ($other && (! $except || (int) $other->id !== (int) $except->id)) {
            throw JsonApiException::conflict('EMAIL_TAKEN', self::EMAIL_TAKEN, $pointer);
        }
    }

    /**
     * Cambia el correo electrónico.
     */
    public function changeEmail(User $user, $email, string $pointer = '/data/attributes/email'): void
    {
        $email = Email::validated($email, $pointer);

        if ($email === $user->email) {
            return;
        }

        $this->ensureEmailFree($email, $user, $pointer);
        $user->forceFill(['email' => $email])->save();
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
