<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\RefreshToken;
use App\Models\Worker;
use App\Support\ExpiredJwtException;
use App\Support\Jwt;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;
use UnexpectedValueException;

/**
 * Emisión, renovación y revocación de tokens (docs/07-algoritmos.md §7.3 y §7.4).
 */
class TokenService
{
    const TYPE_ACCESS = 'access';
    const TYPE_REFRESH = 'refresh';

    /** @var Settings */
    private $settings;

    public function __construct(Settings $settings)
    {
        $this->settings = $settings;
    }

    /**
     * Emite un par de tokens y guarda la huella del de renovación.
     *
     * @return array [accessToken, refreshToken, expiresIn, refreshExpiresIn, refreshTokenModel]
     */
    public function issue(Worker $worker, ?string $deviceName = null): array
    {
        $now = Carbon::now();
        $accessTtl = $this->settings->int('access_token_ttl_minutes') * 60;
        $refreshTtl = $this->settings->int('refresh_token_ttl_days') * 86400;
        $refreshJti = Str::random(40);

        $refresh = RefreshToken::create([
            'worker_id' => $worker->id,
            'token_hash' => hash('sha256', $refreshJti),
            'device_name' => $deviceName,
            'expires_at' => $now->copy()->addSeconds($refreshTtl),
        ]);

        $access = Jwt::encode($this->claims($worker, $now, $accessTtl, self::TYPE_ACCESS, Str::random(40)) + [
            'sid' => $refresh->id,
        ], $this->key());

        $refreshToken = Jwt::encode($this->claims($worker, $now, $refreshTtl, self::TYPE_REFRESH, $refreshJti), $this->key());

        return [
            'accessToken' => $access,
            'refreshToken' => $refreshToken,
            'expiresIn' => $accessTtl,
            'refreshExpiresIn' => $refreshTtl,
            'model' => $refresh,
        ];
    }

    /**
     * Renueva con rotación. Si el token ya se había usado, se considera robado
     * y se revocan todas las sesiones del trabajador.
     */
    public function refresh(string $token, ?string $deviceName = null): array
    {
        $claims = $this->decode($token, self::TYPE_REFRESH);
        $stored = RefreshToken::where('token_hash', hash('sha256', (string) $claims['jti']))->first();

        if (! $stored || (int) $stored->worker_id !== (int) $claims['sub']) {
            throw $this->revoked();
        }

        if ($stored->revoked_at !== null) {
            if ($stored->replaced_by_id !== null) {
                $this->revokeAll((int) $stored->worker_id);
            }

            throw $this->revoked();
        }

        $worker = Worker::find($stored->worker_id);

        if (! $worker) {
            throw $this->revoked();
        }

        return DB::transaction(function () use ($worker, $stored, $deviceName) {
            $pair = $this->issue($worker, $deviceName ?: $stored->device_name);
            $stored->forceFill(['revoked_at' => Carbon::now(), 'replaced_by_id' => $pair['model']->id])->save();

            return $pair;
        });
    }

    /**
     * Valida un token de acceso y devuelve sus claims.
     */
    public function decodeAccess(string $token): array
    {
        return $this->decode($token, self::TYPE_ACCESS);
    }

    public function revoke(int $refreshTokenId): void
    {
        RefreshToken::where('id', $refreshTokenId)->whereNull('revoked_at')->update(['revoked_at' => Carbon::now()]);
    }

    public function revokeAll(int $workerId): void
    {
        RefreshToken::where('worker_id', $workerId)->whereNull('revoked_at')->update(['revoked_at' => Carbon::now()]);
    }

    private function claims(Worker $worker, Carbon $now, int $ttl, string $type, string $jti): array
    {
        return [
            'iss' => config('mitransporte.jwt.issuer'),
            'aud' => config('mitransporte.jwt.audience'),
            'sub' => $worker->id,
            'iat' => $now->getTimestamp(),
            'exp' => $now->getTimestamp() + $ttl,
            'jti' => $jti,
            'typ' => $type,
        ];
    }

    private function decode(string $token, string $type): array
    {
        try {
            $claims = Jwt::decode($token, $this->key());
        } catch (ExpiredJwtException $exception) {
            throw new JsonApiException(401, 'TOKEN_EXPIRED', 'Token caducado', 'El token caducó. Renuévalo o inicia sesión de nuevo.');
        } catch (UnexpectedValueException $exception) {
            throw $this->invalid();
        }

        $valid = isset($claims['typ'], $claims['sub'], $claims['jti'], $claims['aud'])
            && $claims['typ'] === $type
            && $claims['aud'] === config('mitransporte.jwt.audience');

        if (! $valid) {
            throw $this->invalid();
        }

        return $claims;
    }

    private function key(): string
    {
        $key = config('mitransporte.jwt.secret');

        if (! $key) {
            throw new RuntimeException('Falta JWT_SECRET en la configuración.');
        }

        return $key;
    }

    private function invalid(): JsonApiException
    {
        return new JsonApiException(401, 'TOKEN_INVALID', 'Token no válido', 'El token no es válido.');
    }

    private function revoked(): JsonApiException
    {
        return new JsonApiException(401, 'TOKEN_REVOKED', 'Token revocado', 'La sesión se cerró. Inicia sesión de nuevo.');
    }
}
