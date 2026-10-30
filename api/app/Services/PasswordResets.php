<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\Notice;
use App\Models\PasswordReset;
use App\Models\Worker;
use App\Support\CardNumber;
use Carbon\Carbon;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * Restablecer la contraseña sin correo ni SMS: el servidor genera un código,
 * el Administrador se lo envía al trabajador por WhatsApp y el trabajador
 * entra con él; después está obligado a cambiar la contraseña.
 */
class PasswordResets
{
    /** Caracteres del código: sin los que se confunden (0/O, 1/I/L). */
    const ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

    const CODE_LENGTH = 8;

    const MAX_ATTEMPTS = 5;

    /** @var Settings */
    private $settings;

    /** @var Notices */
    private $notices;

    public function __construct(Settings $settings, Notices $notices)
    {
        $this->settings = $settings;
        $this->notices = $notices;
    }

    /**
     * Crea la solicitud y avisa a los Administradores. Si el carné no existe
     * no hace nada (la respuesta es la misma, para no revelar quién está registrado).
     */
    public function request(string $cardNumber, string $phone): void
    {
        $worker = Worker::where('card_number_hash', CardNumber::hashOf($cardNumber))->first();

        if (! $worker) {
            return;
        }

        DB::transaction(function () use ($worker, $phone) {
            // Una nueva solicitud sustituye a la anterior.
            foreach (PasswordReset::where('worker_id', $worker->id)->whereIn('status', [PasswordReset::STATUS_PENDING, PasswordReset::STATUS_SENT])->get() as $previous) {
                $previous->close(PasswordReset::STATUS_CANCELLED);
            }

            $code = $this->generateCode();
            $reset = PasswordReset::create([
                'worker_id' => $worker->id,
                'phone_encrypted' => Crypt::encryptString($phone),
                'code_encrypted' => Crypt::encryptString($code),
                'code_hash' => $this->hash($code),
                'status' => PasswordReset::STATUS_PENDING,
                'expires_at' => Carbon::now()->addHours($this->settings->int('password_reset_ttl_hours')),
            ]);

            foreach ($this->notices->adminIds() as $adminId) {
                Notice::create(['worker_id' => $adminId, 'type' => 'password_reset_requested', 'password_reset_id' => $reset->id]);
            }
        });
    }

    /**
     * Comprueba el código. Si es correcto, lo marca como usado y obliga a
     * cambiar la contraseña; devuelve el trabajador para iniciar su sesión.
     */
    public function redeem(string $cardNumber, string $code): Worker
    {
        $invalid = new JsonApiException(401, 'RESET_CODE_INVALID', 'Código no válido',
            'El código no es correcto o ya no es válido. Pide al Administrador uno nuevo.');

        $worker = preg_match('/^\d{11}$/', $cardNumber)
            ? Worker::where('card_number_hash', CardNumber::hashOf($cardNumber))->first()
            : null;
        $reset = $worker
            ? PasswordReset::where('worker_id', $worker->id)->whereIn('status', [PasswordReset::STATUS_PENDING, PasswordReset::STATUS_SENT])->latest('id')->first()
            : null;

        if (! $reset) {
            throw $invalid;
        }

        if ($reset->expires_at->isPast()) {
            $reset->close(PasswordReset::STATUS_EXPIRED);
            throw $invalid;
        }

        if (! hash_equals($reset->code_hash, $this->hash($code))) {
            $reset->failed_attempts++;
            $reset->failed_attempts >= self::MAX_ATTEMPTS ? $reset->close(PasswordReset::STATUS_EXPIRED) : $reset->save();
            throw $invalid;
        }

        return DB::transaction(function () use ($reset, $worker) {
            $reset->used_at = Carbon::now();
            $reset->close(PasswordReset::STATUS_USED);
            $worker->must_change_password = true;
            $worker->save();
            app(TokenService::class)->revokeAll($worker->id);

            return $worker;
        });
    }

    public function markSent(PasswordReset $reset, Worker $admin): PasswordReset
    {
        if (! $reset->isOpen()) {
            throw JsonApiException::conflict('RESET_NOT_OPEN', 'La solicitud ya no está abierta.');
        }

        $reset->forceFill(['status' => PasswordReset::STATUS_SENT, 'sent_by' => $admin->id, 'sent_at' => Carbon::now()])->save();

        return $reset;
    }

    /**
     * Cierra las solicitudes caducadas (y borra su teléfono y código).
     */
    public function expireOld(): int
    {
        $expired = PasswordReset::whereIn('status', [PasswordReset::STATUS_PENDING, PasswordReset::STATUS_SENT])
            ->where('expires_at', '<=', Carbon::now())->get();

        foreach ($expired as $reset) {
            $reset->close(PasswordReset::STATUS_EXPIRED);
        }

        return $expired->count();
    }

    private function generateCode(): string
    {
        $code = '';

        for ($i = 0; $i < self::CODE_LENGTH; $i++) {
            $code .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
        }

        return $code;
    }

    private function hash(string $code): string
    {
        $normalized = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $code));

        return hash_hmac('sha256', $normalized, (string) config('mitransporte.jwt.secret'));
    }
}
