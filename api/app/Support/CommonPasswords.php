<?php

namespace App\Support;

/**
 * Contraseñas muy usadas que no se aceptan (se comparan en minúsculas).
 */
final class CommonPasswords
{
    const LIST = [
        '12345678', '123456789', '1234567890', '12345678910', '87654321', '11111111', '00000000', '12341234',
        '11223344', '123123123', '147258369', '159753258', '01234567', '1q2w3e4r', '1q2w3e4r5t', 'q1w2e3r4',
        'password', 'password1', 'password12', 'password123', 'passw0rd', 'p@ssw0rd', 'p@ssword', 'contraseña',
        'contrasena', 'contrasena1', 'contraseña1', 'qwerty123', 'qwertyuiop', 'qwerty12', 'qwerty1234', 'asdfghjk',
        'asdfghjkl', 'zxcvbnm1', 'abc12345', 'abcd1234', 'abcdefgh', 'aa123456', 'a1234567', 'iloveyou',
        'teamo123', 'teamo1234', 'admin123', 'admin1234', 'administrador', 'bienvenido', 'bienvenido1', 'welcome1',
        'sunshine', 'princess', 'football', 'baseball', 'superman', 'batman123', 'starwars', 'dragon123',
        'monkey123', 'letmein1', 'trustno1', 'master123', 'mitransporte', 'transporte', 'transporte1', 'guagua123',
        'omnibus1', 'cuba1234', 'mexico123', 'colombia1', 'argentina', 'venezuela', 'espana123', 'barcelona',
        'realmadrid', 'cristiano', 'messi1234', 'pokemon1', 'naruto123', 'micontraseña', 'micontrasena', 'secreto1',
        'secreto123', 'clave123', 'clave1234', 'qazwsxedc', 'zaq12wsx', '1qaz2wsx', 'changeme', 'cambiame',
        'Aa123456', 'Abc12345', 'Qwerty123', 'Password1', 'Password123',
    ];

    public static function contains(string $password): bool
    {
        static $set;

        if ($set === null) {
            $set = array_flip(array_map(function ($item) {
                return mb_strtolower($item, 'UTF-8');
            }, self::LIST));
        }

        return isset($set[mb_strtolower($password, 'UTF-8')]);
    }
}
