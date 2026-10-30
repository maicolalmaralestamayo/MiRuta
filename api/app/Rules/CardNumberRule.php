<?php

namespace App\Rules;

use App\Support\CardNumber;
use Illuminate\Contracts\Validation\Rule;

class CardNumberRule implements Rule
{
    public function passes($attribute, $value)
    {
        return CardNumber::isValid($value);
    }

    public function message()
    {
        return 'El carné debe tener 11 dígitos y empezar por una fecha de nacimiento válida.';
    }
}
