<?php

namespace App\Rules;

use App\Support\Username;
use Illuminate\Contracts\Validation\Rule;

class UsernameRule implements Rule
{
    public function passes($attribute, $value)
    {
        return Username::isValid($value);
    }

    public function message()
    {
        return 'El usuario debe tener de 3 a 30 caracteres, empezar por una letra y usar solo letras sin tilde, números, punto o guion bajo.';
    }
}
