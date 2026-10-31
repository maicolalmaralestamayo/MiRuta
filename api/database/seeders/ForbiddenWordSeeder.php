<?php

namespace Database\Seeders;

use App\Models\ForbiddenWord;
use Illuminate\Database\Seeder;

/**
 * Palabras no permitidas en los nombres de usuario. El Administrador puede
 * añadir más desde la app. Se comparan sin tildes y con los números
 * camuflados convertidos en letras (p3nd3jo → pendejo). Las de 7 letras o
 * más se buscan dentro de todo el usuario; las más cortas, solo como parte
 * separada por punto o guion bajo, para no rechazar palabras normales
 * (por ejemplo "computadora" contiene "puta").
 */
class ForbiddenWordSeeder extends Seeder
{
    const WORDS = [
        'pendejo', 'cabron', 'cabrona', 'puta', 'puto', 'mierda', 'cojones', 'carajo', 'joder', 'maricon',
        'marica', 'pinga', 'singao', 'singada', 'comemierda', 'culo', 'polla', 'tarado', 'idiota', 'imbecil',
        'estupido', 'estupida', 'gilipollas', 'zorra', 'perra', 'malparido', 'hijueputa', 'hijodeputa',
        'mamaguevo', 'mamabicho', 'huevon', 'pajero', 'culero', 'nazi', 'hitler',
    ];

    public function run()
    {
        foreach (self::WORDS as $word) {
            ForbiddenWord::withTrashed()->firstOrCreate(['name' => $word]);
        }
    }
}
