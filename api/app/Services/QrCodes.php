<?php

namespace App\Services;

use App\JsonApi\JsonApiException;
use App\Models\QrNonce;
use App\Models\ServerKey;
use App\Models\User;
use Carbon\Carbon;
use Carbon\CarbonInterface;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;

/**
 * Código QR de la persona (docs/11 §11.8 y §11.9; docs/07-algoritmos.md §7.31).
 *
 * - Clave del servidor ECDSA P-256 (server_keys, privada cifrada con APP_KEY).
 * - Certificado de dispositivo: base64url(json) "." base64url(firma servidor),
 *   json = {"u":<userId>,"k":"<SPKI DER base64>","e":<unix exp>,"v":1}.
 * - QR dinámico: MR1.<certificado>.<base64url(payload)>.<base64url(firma dispositivo)>,
 *   payload = {"u":<userId>,"t":<unix>,"n":"<8 bytes hex>"}.
 * - QR impreso: MRP1.<base64url(json)>.<base64url(firma servidor)>, json = {"u":<userId>,"v":<versión>}.
 *
 * Todas las firmas: ECDSA P-256 con SHA-256, en DER, sobre los bytes JSON
 * (los que resultan de decodificar el segmento base64url, tal cual).
 */
class QrCodes
{
    const DYNAMIC_PREFIX = 'MR1';
    const PRINTED_PREFIX = 'MRP1';

    const KIND_DYNAMIC = 'dynamic';
    const KIND_PRINTED = 'printed';

    /** Diferencia de hora admitida entre los dos teléfonos (±2 min). */
    const CLOCK_SKEW_SECONDS = 120;

    /** Validez del certificado de dispositivo. */
    const CERTIFICATE_DAYS = 30;

    /** Plazo para sincronizar un escaneo hecho sin conexión. */
    const OFFLINE_MAX_AGE_DAYS = 7;

    const CERTIFICATE_VERSION = 1;

    const PURPOSE = 'qr';

    /** @var ServerKey|null */
    private $key;

    /*
    |--------------------------------------------------------------------------
    | Clave del servidor
    |--------------------------------------------------------------------------
    */

    /**
     * Clave del servidor; se crea la primera vez que se necesita.
     */
    public function serverKey(): ServerKey
    {
        if ($this->key) {
            return $this->key;
        }

        $key = ServerKey::where('purpose', self::PURPOSE)->first();

        if (! $key) {
            $resource = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']);

            if ($resource === false || ! openssl_pkey_export($resource, $privatePem)) {
                throw new \RuntimeException('No se pudo crear la clave del servidor para los QR (OpenSSL).');
            }

            $details = openssl_pkey_get_details($resource);

            try {
                $key = ServerKey::create([
                    'purpose' => self::PURPOSE,
                    'public_key' => self::pemToBase64($details['key']),
                    'private_key_encrypted' => Crypt::encryptString($privatePem),
                ]);
            } catch (QueryException $exception) {
                // Otra petición la creó a la vez: vale la suya.
                $key = ServerKey::where('purpose', self::PURPOSE)->firstOrFail();
            }
        }

        return $this->key = $key;
    }

    /**
     * Clave pública del servidor: SPKI DER en base64 (estándar, con relleno).
     */
    public function publicKey(): string
    {
        return $this->serverKey()->public_key;
    }

    public function sign(string $bytes): string
    {
        $private = openssl_pkey_get_private(Crypt::decryptString($this->serverKey()->private_key_encrypted));

        if (! openssl_sign($bytes, $signature, $private, OPENSSL_ALGO_SHA256)) {
            throw new \RuntimeException('No se pudo firmar con la clave del servidor.');
        }

        return $signature;
    }

    public function verifyServer(string $bytes, string $signature): bool
    {
        return self::verifyWith($this->publicKey(), $bytes, $signature);
    }

    /*
    |--------------------------------------------------------------------------
    | Certificado de dispositivo y QR impreso
    |--------------------------------------------------------------------------
    */

    /**
     * Certifica la clave pública del teléfono de la persona (30 días).
     *
     * @return array ['certificate' => string, 'expiresAt' => Carbon, 'publicKey' => string]
     */
    public function issueCertificate(User $user, string $publicKey): array
    {
        $publicKey = self::normalizeDeviceKey($publicKey);

        if ($publicKey === null) {
            throw new JsonApiException(422, 'QR_DEVICE_KEY_INVALID', 'Clave no válida',
                'La clave del teléfono debe ser una clave pública EC P-256 (SPKI DER en base64).', ['pointer' => '/data/attributes/publicKey']);
        }

        $expires = Carbon::now()->addDays(self::CERTIFICATE_DAYS);
        $json = json_encode(['u' => (int) $user->id, 'k' => $publicKey, 'e' => $expires->getTimestamp(), 'v' => self::CERTIFICATE_VERSION], JSON_UNESCAPED_SLASHES);

        return [
            'certificate' => self::base64UrlEncode($json).'.'.self::base64UrlEncode($this->sign($json)),
            'expiresAt' => $expires,
            'publicKey' => $publicKey,
        ];
    }

    /**
     * Texto del QR impreso de la persona (con su versión actual).
     */
    public function printedQr(User $user): string
    {
        $json = json_encode(['u' => (int) $user->id, 'v' => (int) $user->printed_qr_version]);

        return self::PRINTED_PREFIX.'.'.self::base64UrlEncode($json).'.'.self::base64UrlEncode($this->sign($json));
    }

    /**
     * Anula el QR impreso (sube la versión): las copias dejan de valer.
     */
    public function revokePrinted(User $user): User
    {
        DB::table('users')->where('id', $user->id)->increment('printed_qr_version');

        return $user->fresh();
    }

    /**
     * Al entrar por primera vez en la app con su teléfono, el QR impreso se
     * anula y pasa a usar el del teléfono (docs/11 §11.9).
     */
    public function switchToPhone(User $user): void
    {
        if ($user->has_phone) {
            return;
        }

        DB::table('users')->where('id', $user->id)->update([
            'has_phone' => true,
            'printed_qr_version' => DB::raw('printed_qr_version + 1'),
            'updated_at' => Carbon::now(),
        ]);
        $user->has_phone = true;
        $user->printed_qr_version = (int) $user->printed_qr_version + 1;
        $user->syncOriginal();
    }

    /*
    |--------------------------------------------------------------------------
    | Verificación
    |--------------------------------------------------------------------------
    */

    /**
     * Comprueba un QR leído a la hora $scannedAt (la del teléfono que escanea;
     * sin conexión, la que guardó). No gasta el código: ver consume().
     *
     * @return array ['user' => User, 'kind' => dynamic|printed, 'nonce' => ?string, 'issuedAt' => ?Carbon]
     */
    public function verify(string $qr, ?CarbonInterface $scannedAt = null, string $pointer = '/data/attributes/qr'): array
    {
        $now = Carbon::now();
        $scannedAt = $scannedAt ? Carbon::instance($scannedAt) : $now->copy();

        if ($scannedAt->greaterThan($now->copy()->addSeconds(self::CLOCK_SKEW_SECONDS))) {
            throw new JsonApiException(422, 'QR_SCAN_TIME_INVALID', 'Hora no válida',
                'La hora del escaneo es posterior a la del servidor. Revise la hora del teléfono.', ['pointer' => '/data/attributes/scannedAt']);
        }

        if ($scannedAt->lessThan($now->copy()->subDays(self::OFFLINE_MAX_AGE_DAYS))) {
            throw new JsonApiException(422, 'QR_SCAN_TOO_OLD', 'Escaneo demasiado antiguo',
                'El escaneo tiene más de '.self::OFFLINE_MAX_AGE_DAYS.' días y ya no se puede sincronizar.', ['pointer' => '/data/attributes/scannedAt']);
        }

        $parts = explode('.', trim($qr));

        if ($parts[0] === self::PRINTED_PREFIX && count($parts) === 3) {
            return $this->verifyPrinted($parts, $pointer);
        }

        if ($parts[0] === self::DYNAMIC_PREFIX && count($parts) === 5) {
            return $this->verifyDynamic($parts, $scannedAt, $pointer);
        }

        throw $this->invalid($pointer);
    }

    /**
     * Gasta el código dinámico (un solo uso). Si ya se usó para lo mismo
     * (reintento de la sincronización) devuelve la fila anterior; si se usó
     * para otra cosa, 409 QR_ALREADY_USED.
     */
    public function consume(array $verified, string $purpose, ?callable $sameUse = null): ?QrNonce
    {
        if ($verified['kind'] !== self::KIND_DYNAMIC) {
            return null;
        }

        $userId = (int) $verified['user']->id;
        $existing = QrNonce::withTrashed()->where('user_id', $userId)->where('nonce', $verified['nonce'])->first();

        if (! $existing) {
            try {
                return QrNonce::create([
                    'user_id' => $userId,
                    'nonce' => $verified['nonce'],
                    'purpose' => $purpose,
                    'expires_at' => $verified['issuedAt']->copy()->addSeconds(self::CLOCK_SKEW_SECONDS)->addDays(self::OFFLINE_MAX_AGE_DAYS),
                ]);
            } catch (QueryException $exception) {
                $existing = QrNonce::withTrashed()->where('user_id', $userId)->where('nonce', $verified['nonce'])->first();
            }
        }

        if ($existing && $sameUse && $existing->purpose === $purpose && $sameUse($existing)) {
            $existing->setAttribute('repeated', true);

            return $existing;
        }

        throw JsonApiException::conflict('QR_ALREADY_USED', 'Este código QR ya se usó. Cada código vale una sola vez: pida que lo muestre de nuevo.', '/data/attributes/qr');
    }

    /**
     * Borra los códigos gastados que ya no pueden volver a presentarse.
     */
    public function purgeExpiredNonces(): int
    {
        return QrNonce::withTrashed()->where('expires_at', '<', Carbon::now())->forceDelete();
    }

    private function verifyDynamic(array $parts, Carbon $scannedAt, string $pointer): array
    {
        list(, $certificateJson, $certificateSignature, $payloadJson, $deviceSignature) = $parts;
        $certificateBytes = self::base64UrlDecode($certificateJson);
        $certificateSig = self::base64UrlDecode($certificateSignature);
        $payloadBytes = self::base64UrlDecode($payloadJson);
        $deviceSig = self::base64UrlDecode($deviceSignature);

        if ($certificateBytes === null || $certificateSig === null || $payloadBytes === null || $deviceSig === null) {
            throw $this->invalid($pointer);
        }

        $certificate = json_decode($certificateBytes, true);
        $payload = json_decode($payloadBytes, true);

        if (! is_array($certificate) || ! isset($certificate['u'], $certificate['k'], $certificate['e'], $certificate['v'])
            || ! is_array($payload) || ! isset($payload['u'], $payload['t'], $payload['n'])
            || ! is_string($payload['n']) || ! preg_match('/^[0-9a-f]{16}$/', $payload['n'])
            || ! is_int($payload['t']) || ! is_int($payload['u']) || ! is_int($certificate['u']) || ! is_string($certificate['k'])) {
            throw $this->invalid($pointer);
        }

        if (! $this->verifyServer($certificateBytes, $certificateSig)) {
            throw new JsonApiException(422, 'QR_CERTIFICATE_INVALID', 'Código QR no válido',
                'El certificado del teléfono no lo firmó este servidor.', ['pointer' => $pointer]);
        }

        if ((int) $certificate['u'] !== (int) $payload['u']) {
            throw new JsonApiException(422, 'QR_CERTIFICATE_INVALID', 'Código QR no válido',
                'El certificado del teléfono es de otra persona.', ['pointer' => $pointer]);
        }

        if ((int) $certificate['e'] < $scannedAt->getTimestamp()) {
            throw new JsonApiException(422, 'QR_CERTIFICATE_EXPIRED', 'Certificado caducado',
                'El certificado del teléfono caducó. La persona debe abrir la app con conexión para renovarlo.', ['pointer' => $pointer]);
        }

        if (! self::verifyWith($certificate['k'], $payloadBytes, $deviceSig)) {
            throw new JsonApiException(422, 'QR_SIGNATURE_INVALID', 'Código QR no válido',
                'La firma del código QR no es válida.', ['pointer' => $pointer]);
        }

        if (abs($payload['t'] - $scannedAt->getTimestamp()) > self::CLOCK_SKEW_SECONDS) {
            throw new JsonApiException(422, 'QR_EXPIRED', 'Código QR caducado',
                'El código QR caducó (o la hora de los teléfonos difiere en más de 2 minutos). Pida que lo muestre de nuevo.', ['pointer' => $pointer]);
        }

        return [
            'user' => $this->activeUser((int) $payload['u'], $pointer),
            'kind' => self::KIND_DYNAMIC,
            'nonce' => $payload['n'],
            'issuedAt' => Carbon::createFromTimestamp($payload['t']),
        ];
    }

    private function verifyPrinted(array $parts, string $pointer): array
    {
        $bytes = self::base64UrlDecode($parts[1]);
        $signature = self::base64UrlDecode($parts[2]);

        if ($bytes === null || $signature === null) {
            throw $this->invalid($pointer);
        }

        $json = json_decode($bytes, true);

        if (! is_array($json) || ! isset($json['u'], $json['v']) || ! is_int($json['u']) || ! is_int($json['v'])) {
            throw $this->invalid($pointer);
        }

        if (! $this->verifyServer($bytes, $signature)) {
            throw new JsonApiException(422, 'QR_SIGNATURE_INVALID', 'Código QR no válido',
                'La firma del código QR no es válida.', ['pointer' => $pointer]);
        }

        $user = $this->activeUser($json['u'], $pointer);

        if ($user->has_phone || (int) $user->printed_qr_version !== $json['v']) {
            throw new JsonApiException(422, 'QR_REVOKED', 'QR impreso anulado',
                'Este QR impreso fue anulado. Si la persona usa la app, debe mostrar el QR de su teléfono.', ['pointer' => $pointer]);
        }

        return ['user' => $user, 'kind' => self::KIND_PRINTED, 'nonce' => null, 'issuedAt' => null];
    }

    private function activeUser(int $id, string $pointer): User
    {
        $user = User::find($id);

        if (! $user) {
            throw new JsonApiException(422, 'QR_USER_INACTIVE', 'Persona no activa',
                'La persona de este código QR no existe o su cuenta está desactivada.', ['pointer' => $pointer]);
        }

        return $user;
    }

    private function invalid(string $pointer): JsonApiException
    {
        return new JsonApiException(422, 'QR_INVALID', 'Código QR no válido',
            'El código QR no es de MiRuta o está dañado.', ['pointer' => $pointer]);
    }

    /*
    |--------------------------------------------------------------------------
    | Codificaciones
    |--------------------------------------------------------------------------
    */

    public static function base64UrlEncode(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }

    public static function base64UrlDecode(string $text): ?string
    {
        if ($text === '' || ! preg_match('/^[A-Za-z0-9_-]+$/', $text)) {
            return null;
        }

        $decoded = base64_decode(strtr($text, '-_', '+/').str_repeat('=', (4 - strlen($text) % 4) % 4), true);

        return $decoded === false ? null : $decoded;
    }

    public static function pemToBase64(string $pem): string
    {
        return preg_replace('/-----[A-Z ]+-----|\s+/', '', $pem);
    }

    public static function base64ToPem(string $base64): string
    {
        return "-----BEGIN PUBLIC KEY-----\n".chunk_split($base64, 64, "\n")."-----END PUBLIC KEY-----\n";
    }

    /**
     * Clave pública P-256 en SPKI DER base64 (estándar), o null si no lo es.
     */
    public static function normalizeDeviceKey(string $publicKey): ?string
    {
        $der = base64_decode(trim($publicKey), true);

        if ($der === false || strlen($der) < 60 || strlen($der) > 200) {
            return null;
        }

        $base64 = base64_encode($der);
        $key = @openssl_pkey_get_public(self::base64ToPem($base64));

        if ($key === false) {
            return null;
        }

        $details = openssl_pkey_get_details($key);

        if (! $details || $details['type'] !== OPENSSL_KEYTYPE_EC || ! isset($details['ec']['curve_name']) || $details['ec']['curve_name'] !== 'prime256v1') {
            return null;
        }

        return $base64;
    }

    public static function verifyWith(string $publicKeyBase64, string $bytes, string $signature): bool
    {
        $key = @openssl_pkey_get_public(self::base64ToPem($publicKeyBase64));

        return $key !== false && @openssl_verify($bytes, $signature, $key, OPENSSL_ALGO_SHA256) === 1;
    }
}
