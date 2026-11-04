<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\AccessRecovery;
use App\Models\Installation;
use App\Models\Notice;
use App\Models\User;
use App\Support\IdentityCard;
use Carbon\Carbon;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * «Olvidé algo» (docs/11 §11.7): la persona indica qué olvidó, su carné y
 * un teléfono; solo el Administrador la aprueba, tras verificarlo por una
 * tercera vía. Al aprobarla se propone una contraseña nueva (hay que
 * cambiarla al entrar) y se comunica solo lo pedido: al Administrador en la
 * respuesta y a la instalación que la pidió.
 */
class AccessRecoveries
{
    /** @var Settings */
    private $settings;

    /** @var Notices */
    private $notices;

    /** @var Passwords */
    private $passwords;

    public function __construct(Settings $settings, Notices $notices, Passwords $passwords)
    {
        $this->settings = $settings;
        $this->notices = $notices;
        $this->passwords = $passwords;
    }

    /**
     * Crea la solicitud. La respuesta no dice si los datos coinciden.
     */
    public function request(Installation $installation, bool $forgotUsername, bool $forgotPassword, string $identityCard, string $phone): AccessRecovery
    {
        if (! $forgotUsername && ! $forgotPassword) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Datos no válidos', 'Indique qué olvidó: el usuario, la contraseña o los dos.',
                ['pointer' => '/data/attributes/forgotUsername']);
        }

        $card = IdentityCard::validated($identityCard);

        $limit = $this->settings->int('access_recovery_max_per_hour');
        $recent = AccessRecovery::where('installation_id', $installation->id)->where('created_at', '>=', Carbon::now()->subHour())->count();

        if ($recent >= $limit) {
            throw new JsonApiException(429, 'TOO_MANY_REQUESTS', 'Demasiadas solicitudes', 'Espere un rato antes de enviar otra solicitud.');
        }

        $user = User::findByIdentityCard($card);

        return DB::transaction(function () use ($installation, $forgotUsername, $forgotPassword, $card, $phone, $user) {
            // Una nueva sustituye a las abiertas de esta instalación.
            foreach (AccessRecovery::where('installation_id', $installation->id)->whereIn('status', [AccessRecovery::STATUS_PENDING, AccessRecovery::STATUS_APPROVED])->get() as $previous) {
                $previous->close(AccessRecovery::STATUS_EXPIRED);
            }

            $recovery = AccessRecovery::create([
                'installation_id' => $installation->id,
                'forgot_username' => $forgotUsername,
                'forgot_password' => $forgotPassword,
                'identity_card_encrypted' => Crypt::encryptString($card),
                'identity_card_hash' => IdentityCard::hash($card),
                'phone_encrypted' => Crypt::encryptString($phone),
                'user_id' => $user ? $user->id : null,
                'status' => AccessRecovery::STATUS_PENDING,
                'expires_at' => Carbon::now()->addHours($this->settings->int('access_recovery_ttl_hours')),
            ]);

            foreach ($this->notices->adminIds() as $adminId) {
                Notice::create(['user_id' => $adminId, 'type' => Notice::TYPE_ACCESS_RECOVERY_REQUESTED, 'access_recovery_id' => $recovery->id]);
            }

            return $recovery;
        });
    }

    public function approve(AccessRecovery $recovery, User $admin): AccessRecovery
    {
        $this->ensurePending($recovery);

        if (! $recovery->user_id || ! $recovery->user || $recovery->user->trashed()) {
            throw JsonApiException::conflict('RECOVERY_NOT_MATCHED', 'El carné no coincide con ninguna persona con cuenta activa: solo se puede rechazar.');
        }

        return DB::transaction(function () use ($recovery, $admin) {
            $password = null;

            if ($recovery->forgot_password) {
                $user = $recovery->user;
                $password = $this->passwords->suggest();
                $this->passwords->set($user, $password);
                // Contraseña puesta por otro: hay que cambiarla al entrar.
                $user->forceFill(['must_change_password' => true])->save();
                app(TokenService::class)->revokeAll($user->id);
            }

            $recovery->forceFill([
                'status' => AccessRecovery::STATUS_APPROVED,
                'resolved_by' => $admin->id,
                'resolved_at' => Carbon::now(),
                'password_encrypted' => $password === null ? null : Crypt::encryptString($password),
            ])->save();

            return $recovery;
        });
    }

    public function reject(AccessRecovery $recovery, User $admin): AccessRecovery
    {
        $this->ensurePending($recovery);
        $recovery->forceFill(['resolved_by' => $admin->id, 'resolved_at' => Carbon::now()])->save();
        $recovery->close(AccessRecovery::STATUS_REJECTED);

        return $recovery;
    }

    /**
     * La instalación consulta su solicitud (cierra las caducadas).
     */
    public function readByInstallation(AccessRecovery $recovery): AccessRecovery
    {
        $this->expireIfNeeded($recovery);

        return $recovery;
    }

    /**
     * Una vez que la instalación leyó lo aprobado, se da por terminada (la
     * contraseña propuesta ya no se vuelve a mostrar).
     */
    public function completeAfterReading(AccessRecovery $recovery): void
    {
        if ($recovery->status === AccessRecovery::STATUS_APPROVED) {
            $recovery->close(AccessRecovery::STATUS_COMPLETED);
        }
    }

    /**
     * Cierra las solicitudes caducadas (y borra su teléfono).
     */
    public function expireOld(): int
    {
        $expired = AccessRecovery::whereIn('status', [AccessRecovery::STATUS_PENDING, AccessRecovery::STATUS_APPROVED])
            ->where('expires_at', '<=', Carbon::now())->get();

        foreach ($expired as $recovery) {
            $recovery->close(AccessRecovery::STATUS_EXPIRED);
        }

        return $expired->count();
    }

    private function ensurePending(AccessRecovery $recovery): void
    {
        $this->expireIfNeeded($recovery);

        if ($recovery->status !== AccessRecovery::STATUS_PENDING) {
            throw JsonApiException::conflict('RECOVERY_NOT_PENDING', 'La solicitud ya no está pendiente.');
        }
    }

    private function expireIfNeeded(AccessRecovery $recovery): void
    {
        if ($recovery->isOpen() && $recovery->expires_at->lte(Carbon::now())) {
            $recovery->close(AccessRecovery::STATUS_EXPIRED);
        }
    }
}
