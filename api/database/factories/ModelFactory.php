<?php

/** @var \Illuminate\Database\Eloquent\Factory $factory */

use App\Models\Rank;
use App\Models\Worker;
use App\Support\CardNumber;
use Faker\Generator as Faker;
use Illuminate\Support\Facades\Hash;

/*
|--------------------------------------------------------------------------
| Model Factories
|--------------------------------------------------------------------------
*/

$factory->define(Rank::class, function (Faker $faker) {
    return [
        'name' => $faker->unique()->words(2, true),
        'precedence' => $faker->unique()->numberBetween(100, 999),
    ];
});

$factory->define(Worker::class, function (Faker $faker) {
    // Carné válido: fecha de nacimiento del siglo XX (7.º dígito entre 0 y 5).
    $birth = $faker->dateTimeBetween('-60 years', '-27 years');
    $card = CardNumber::tryParse($birth->format('ymd').$faker->numberBetween(0, 5).$faker->numerify('####'));

    return [
        'card_number_encrypted' => $card->encrypt(),
        'card_number_hash' => $card->hash(),
        'first_name' => $faker->firstName,
        'last_name' => $faker->lastName.' '.$faker->lastName,
        'sex' => $card->sex(),
        'password' => Hash::make('secreto123'),
        'rank_id' => function () {
            return factory(Rank::class)->create()->id;
        },
        'is_admin' => false,
    ];
});
