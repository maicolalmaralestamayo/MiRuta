<?php

namespace App\Support;

use Carbon\Carbon;
use UnexpectedValueException;

/**
 * JSON Web Token (RFC 7519) firmado con HMAC-SHA256 (RFC 7518, "HS256").
 *
 * Implementación propia y mínima para no depender de una librería cuya API
 * cambie al actualizar PHP.
 */
final class Jwt
{
    const ALGORITHM = 'HS256';

    /** Margen en segundos para relojes desajustados al validar exp, nbf e iat. */
    const LEEWAY = 30;

    public static function encode(array $claims, string $key): string
    {
        $header = ['typ' => 'JWT', 'alg' => self::ALGORITHM];
        $segments = [self::base64UrlEncode(json_encode($header)), self::base64UrlEncode(json_encode($claims))];
        $segments[] = self::base64UrlEncode(self::sign(implode('.', $segments), $key));

        return implode('.', $segments);
    }

    /**
     * Verifica la firma y las fechas y devuelve los claims.
     *
     * @throws ExpiredJwtException si el token caducó
     * @throws UnexpectedValueException si el token no es válido
     */
    public static function decode(string $token, string $key): array
    {
        $segments = explode('.', $token);

        if (count($segments) !== 3) {
            throw new UnexpectedValueException('El token no tiene tres partes.');
        }

        list($headerSegment, $claimsSegment, $signatureSegment) = $segments;
        $header = json_decode(self::base64UrlDecode($headerSegment), true);
        $claims = json_decode(self::base64UrlDecode($claimsSegment), true);

        if (! is_array($header) || ! is_array($claims)) {
            throw new UnexpectedValueException('El token no es JSON válido.');
        }

        if (! isset($header['alg']) || $header['alg'] !== self::ALGORITHM) {
            throw new UnexpectedValueException('Algoritmo de firma no admitido.');
        }

        $expected = self::sign($headerSegment.'.'.$claimsSegment, $key);

        if (! hash_equals($expected, self::base64UrlDecode($signatureSegment))) {
            throw new UnexpectedValueException('Firma no válida.');
        }

        $now = Carbon::now()->getTimestamp();

        if (isset($claims['nbf']) && $claims['nbf'] > $now + self::LEEWAY) {
            throw new UnexpectedValueException('El token aún no es válido.');
        }

        if (isset($claims['iat']) && $claims['iat'] > $now + self::LEEWAY) {
            throw new UnexpectedValueException('El token se emitió en el futuro.');
        }

        if (! isset($claims['exp']) || ! is_int($claims['exp'])) {
            throw new UnexpectedValueException('El token no tiene caducidad.');
        }

        if ($claims['exp'] <= $now - self::LEEWAY) {
            throw new ExpiredJwtException('El token caducó.');
        }

        return $claims;
    }

    private static function sign(string $input, string $key): string
    {
        return hash_hmac('sha256', $input, $key, true);
    }

    private static function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $data): string
    {
        $decoded = base64_decode(strtr($data, '-_', '+/'), true);

        return $decoded === false ? '' : $decoded;
    }
}
