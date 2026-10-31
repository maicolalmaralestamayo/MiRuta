<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\ActivationCode;
use App\Models\Entity;
use App\Models\ReleasedUsername;
use App\Models\User;
use App\Models\Worker;
use App\Support\Username;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Cuentas y trabajadores (docs/08-version-2.md §8.3).
 */
class Accounts
{
    /** Caracteres de los códigos: sin los que se confunden (0/O, 1/I/L). */
    const CODE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    const CODE_LENGTH = 8;

    const MAX_CODE_ATTEMPTS = 5;

    /**
     * Intentos de la transacción: si dos registros simultáneos en un sistema
     * vacío chocan, se reintenta y el segundo ya no será Administrador.
     */
    const TRANSACTION_ATTEMPTS = 3;

    /** @var Passwords */
    private $passwords;

    /** @var Settings */
    private $settings;

    public function __construct(Passwords $passwords, Settings $settings)
    {
        $this->passwords = $passwords;
        $this->settings = $settings;
    }

    /**
     * Paso 1 del registro: la cuenta. La primera de todas es la del Administrador.
     *
     * @param array $names [first_name, middle_name, first_surname, second_surname]
     */
    public function register(array $names, string $username, string $password): User
    {
        $username = $this->ensureUsernameAvailable($username);
        $this->passwords->validate($password, array_merge([$username], array_values($names)));

        return DB::transaction(function () use ($names, $username, $password) {
            $isFirst = ! User::withTrashed()->lockForUpdate()->exists();
            $user = User::create($names + ['username' => $username, 'is_admin' => $isFirst]);
            $this->passwords->set($user, $password);

            return $user;
        }, self::TRANSACTION_ATTEMPTS);
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
            throw JsonApiException::conflict('USERNAME_TAKEN', 'Ese usuario ya existe o se dejó de usar hace poco. Elige otro.', $pointer);
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

    /**
     * Paso 2 del registro: unirse a una Entidad con el Pase.
     */
    public function joinEntity(User $user, string $abbreviation, int $pass, string $sex, int $rankId): Worker
    {
        if ($user->isAdmin()) {
            throw new JsonApiException(409, 'ADMIN_HAS_NO_ENTITY', 'No corresponde', 'El Administrador no pertenece a ninguna Entidad.');
        }

        if (Worker::withTrashed()->where('user_id', $user->id)->exists()) {
            throw JsonApiException::conflict('ALREADY_IN_ENTITY', 'Ya perteneces a una Entidad.');
        }

        $entity = $this->entityOrFail($abbreviation);
        $this->ensurePassFree($entity->id, $pass);

        $worker = Worker::create([
            'user_id' => $user->id, 'entity_id' => $entity->id, 'pass' => $pass, 'sex' => $sex, 'rank_id' => $rankId,
        ]);
        $user->refreshRoles();

        return $worker;
    }

    /**
     * Un superior registra a un trabajador sin teléfono: la cuenta queda sin
     * usuario ni contraseña y se genera su código de activación.
     *
     * @return array [Worker, string código]
     */
    public function registerBySuperior(User $actor, Entity $entity, array $names, int $pass, string $sex, int $rankId): array
    {
        $this->ensurePassFree($entity->id, $pass);

        return DB::transaction(function () use ($actor, $entity, $names, $pass, $sex, $rankId) {
            $user = User::create($names);
            $worker = Worker::create([
                'user_id' => $user->id, 'entity_id' => $entity->id, 'pass' => $pass, 'sex' => $sex, 'rank_id' => $rankId,
            ]);

            return [$worker, $this->issueActivationCode($user, $actor)];
        });
    }

    /**
     * Código de activación nuevo; anula los anteriores sin usar.
     */
    public function issueActivationCode(User $user, User $actor): string
    {
        if ($user->isActivated()) {
            throw JsonApiException::conflict('ALREADY_ACTIVATED', 'Esa cuenta ya está activada.');
        }

        ActivationCode::where('user_id', $user->id)->whereNull('used_at')->delete();

        $code = self::generateCode();
        ActivationCode::create([
            'user_id' => $user->id,
            'code_hash' => self::hashCode($code),
            'expires_at' => Carbon::now()->addDays($this->settings->int('activation_code_ttl_days')),
            'created_by' => $actor->id,
        ]);

        return $code;
    }

    public function activationExpiresAt(User $user): ?Carbon
    {
        $code = ActivationCode::where('user_id', $user->id)->whereNull('used_at')->latest('id')->first();

        return $code ? $code->expires_at : null;
    }

    /**
     * "Ya me registró un superior": con la Entidad, el Pase y el código, el
     * trabajador elige su usuario y su contraseña.
     */
    public function activate(string $abbreviation, int $pass, string $code, string $username, string $password): User
    {
        $invalid = new JsonApiException(422, 'ACTIVATION_INVALID', 'Datos no válidos',
            'La Entidad, el Pase o el código no son correctos, o el código caducó. Pide uno nuevo a tu superior.');

        $entity = Entity::findByAbbreviation($abbreviation);
        $worker = $entity ? Worker::where('entity_id', $entity->id)->where('pass', $pass)->first() : null;
        $user = $worker ? $worker->user : null;

        if (! $user || $user->trashed() || $user->isActivated()) {
            throw $invalid;
        }

        $activation = ActivationCode::where('user_id', $user->id)->whereNull('used_at')->latest('id')->first();

        if (! $activation || $activation->expires_at->isPast() || $activation->failed_attempts >= self::MAX_CODE_ATTEMPTS) {
            throw $invalid;
        }

        if (! hash_equals($activation->code_hash, self::hashCode($code))) {
            $activation->increment('failed_attempts');
            throw $invalid;
        }

        $username = $this->ensureUsernameAvailable($username, $user);
        $this->passwords->validate($password, [$username, $user->first_name, $user->middle_name, $user->first_surname, $user->second_surname]);

        return DB::transaction(function () use ($user, $activation, $username, $password) {
            $user->username = $username;
            $user->save();
            $this->passwords->set($user, $password);
            $activation->forceFill(['used_at' => Carbon::now()])->save();

            return $user;
        });
    }

    public function entityOrFail(string $abbreviation, string $pointer = '/data/attributes/entityAbbreviation'): Entity
    {
        $entity = Entity::findByAbbreviation($abbreviation);

        if (! $entity) {
            throw new JsonApiException(422, 'ENTITY_NOT_FOUND', 'Entidad no encontrada',
                'No hay ninguna Entidad con esa abreviatura. Pregúntala a tu superior.', ['pointer' => $pointer]);
        }

        return $entity;
    }

    public function ensurePassFree(int $entityId, int $pass, ?int $exceptWorkerId = null, string $pointer = '/data/attributes/pass'): void
    {
        $query = Worker::withTrashed()->where('entity_id', $entityId)->where('pass', $pass);

        if ($exceptWorkerId !== null) {
            $query->where('id', '<>', $exceptWorkerId);
        }

        if ($query->exists()) {
            throw JsonApiException::conflict('PASS_TAKEN',
                'Ya hay un trabajador con ese Pase en la Entidad. Si un superior te registró, usa "Ya me registró un superior".', $pointer);
        }
    }

    public static function generateCode(): string
    {
        $code = '';

        for ($i = 0; $i < self::CODE_LENGTH; $i++) {
            $code .= self::CODE_ALPHABET[random_int(0, strlen(self::CODE_ALPHABET) - 1)];
        }

        return $code;
    }

    /**
     * Sin guiones ni espacios y en mayúsculas: "abcd-efgh" vale como "ABCDEFGH".
     */
    public static function hashCode(string $code): string
    {
        return hash_hmac('sha256', strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code)), (string) config('app.key'));
    }
}
