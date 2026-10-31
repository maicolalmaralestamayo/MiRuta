<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\AccessRecovery;
use App\Models\Entity;
use App\Models\Installation;
use App\Models\Notice;
use App\Models\User;
use App\Models\Worker;
use Carbon\Carbon;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * "No puedo entrar" (docs/08-version-2.md §8.6): el trabajador indica qué
 * olvidó, su Entidad, su Pase y un teléfono; el Administrador lo verifica
 * por su cuenta y aprueba o rechaza. Lo aprobado solo vale en la instalación
 * desde la que se pidió.
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
    public function request(Installation $installation, bool $forgotUsername, bool $forgotPassword, string $abbreviation, int $pass, string $phone): AccessRecovery
    {
        if (! $forgotUsername && ! $forgotPassword) {
            throw new JsonApiException(422, 'VALIDATION_ERROR', 'Datos no válidos', 'Indica qué olvidaste: el usuario, la contraseña o los dos.',
                ['pointer' => '/data/attributes/forgotUsername']);
        }

        $limit = $this->settings->int('access_recovery_max_per_hour');
        $recent = AccessRecovery::where('installation_id', $installation->id)->where('created_at', '>=', Carbon::now()->subHour())->count();

        if ($recent >= $limit) {
            throw new JsonApiException(429, 'TOO_MANY_REQUESTS', 'Demasiadas solicitudes', 'Espera un rato antes de enviar otra solicitud.');
        }

        $entity = Entity::findByAbbreviation($abbreviation);
        $worker = $entity ? Worker::where('entity_id', $entity->id)->where('pass', $pass)->first() : null;

        return DB::transaction(function () use ($installation, $forgotUsername, $forgotPassword, $abbreviation, $pass, $phone, $worker) {
            // Una nueva sustituye a las abiertas de esta instalación.
            foreach (AccessRecovery::where('installation_id', $installation->id)->whereIn('status', [AccessRecovery::STATUS_PENDING, AccessRecovery::STATUS_APPROVED])->get() as $previous) {
                $previous->close(AccessRecovery::STATUS_EXPIRED);
            }

            $recovery = AccessRecovery::create([
                'installation_id' => $installation->id,
                'forgot_username' => $forgotUsername,
                'forgot_password' => $forgotPassword,
                'entity_abbreviation' => Entity::normalizeAbbreviation($abbreviation),
                'pass' => $pass,
                'phone_encrypted' => Crypt::encryptString($phone),
                'worker_id' => $worker && $worker->user && $worker->user->isActivated() ? $worker->id : null,
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

        if (! $recovery->worker_id) {
            throw JsonApiException::conflict('RECOVERY_NOT_MATCHED', 'Los datos no coinciden con ningún trabajador con cuenta activada: solo se puede rechazar.');
        }

        $recovery->forceFill(['status' => AccessRecovery::STATUS_APPROVED, 'resolved_by' => $admin->id, 'resolved_at' => Carbon::now()])->save();

        return $recovery;
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
     * Si solo olvidó el usuario y ya se aprobó, se da por terminada una vez
     * que la instalación lo ha leído.
     */
    public function completeIfOnlyUsername(AccessRecovery $recovery): void
    {
        if ($recovery->status === AccessRecovery::STATUS_APPROVED && ! $recovery->forgot_password) {
            $recovery->close(AccessRecovery::STATUS_COMPLETED);
        }
    }

    /**
     * Contraseña nueva tras la aprobación. Cierra las demás sesiones y
     * devuelve la cuenta para iniciar sesión.
     */
    public function setPassword(AccessRecovery $recovery, string $password): User
    {
        $this->expireIfNeeded($recovery);

        if ($recovery->status !== AccessRecovery::STATUS_APPROVED || ! $recovery->forgot_password) {
            throw JsonApiException::conflict('RECOVERY_NOT_APPROVED', 'La solicitud no está aprobada para cambiar la contraseña.');
        }

        $user = $recovery->worker->user;
        $this->passwords->validate($password, [$user->username, $user->first_name, $user->middle_name, $user->first_surname, $user->second_surname], $user);

        return DB::transaction(function () use ($recovery, $user, $password) {
            $this->passwords->set($user, $password);
            app(TokenService::class)->revokeAll($user->id);
            $recovery->close(AccessRecovery::STATUS_COMPLETED);

            return $user;
        });
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
