<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Worker;
use App\Support\CardNumber;
use App\Support\Username;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

/**
 * Registro de trabajadores (docs/07-algoritmos.md §7.2).
 */
class WorkerRegistration
{
    /**
     * Intentos de la transacción: si dos registros simultáneos en un sistema
     * vacío chocan (bloqueo mutuo), se reintenta y el segundo ya no será
     * Administrador.
     */
    const TRANSACTION_ATTEMPTS = 3;

    public function register(CardNumber $cardNumber, string $username, string $firstName, string $lastName, int $rankId, string $password): Worker
    {
        $hash = $cardNumber->hash();
        $username = Username::normalize($username);

        if (Worker::withTrashed()->where('card_number_hash', $hash)->exists()) {
            throw JsonApiException::conflict('CARD_NUMBER_TAKEN', 'Ya hay un trabajador registrado con ese carné.', '/data/attributes/cardNumber');
        }

        self::ensureUsernameFree($username);

        return DB::transaction(function () use ($cardNumber, $hash, $username, $firstName, $lastName, $rankId, $password) {
            $isFirst = ! Worker::withTrashed()->lockForUpdate()->exists();

            return Worker::create([
                'username' => $username,
                'card_number_encrypted' => $cardNumber->encrypt(),
                'card_number_hash' => $hash,
                'first_name' => $firstName,
                'last_name' => $lastName,
                'sex' => $cardNumber->sex(),
                'password' => Hash::make($password),
                'rank_id' => $rankId,
                'is_admin' => $isFirst,
            ]);
        }, self::TRANSACTION_ATTEMPTS);
    }

    /**
     * 409 USERNAME_TAKEN si otro trabajador (activo o no) ya lo usa.
     */
    public static function ensureUsernameFree(string $username, ?Worker $worker = null): void
    {
        if (Username::taken($username, $worker ? $worker->id : null)) {
            throw JsonApiException::conflict('USERNAME_TAKEN', 'Ese usuario ya existe. Elige otro.', '/data/attributes/username');
        }
    }
}
