<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Mensajes de validación
    |--------------------------------------------------------------------------
    */

    'after_or_equal' => 'El campo :attribute debe ser una fecha igual o posterior a :date.',
    'array' => 'El campo :attribute debe ser una lista.',
    'between' => [
        'numeric' => 'El campo :attribute debe estar entre :min y :max.',
    ],
    'boolean' => 'El campo :attribute debe ser verdadero o falso.',
    'date' => 'El campo :attribute no es una fecha válida.',
    'date_format' => 'El campo :attribute no tiene el formato :format.',
    'file' => 'El campo :attribute debe ser un archivo.',
    'image' => 'El campo :attribute debe ser una imagen.',
    'mimes' => 'El campo :attribute debe ser un archivo de tipo: :values.',
    'uploaded' => 'No se pudo subir :attribute.',
    'exists' => 'El valor de :attribute no existe.',
    'in' => 'El valor de :attribute no es válido.',
    'integer' => 'El campo :attribute debe ser un número entero.',
    'max' => [
        'file' => 'El campo :attribute no puede pesar más de :max kilobytes.',
        'numeric' => 'El campo :attribute no puede ser mayor que :max.',
        'string' => 'El campo :attribute no puede tener más de :max caracteres.',
        'after_or_equal' => 'El campo :attribute debe ser una fecha igual o posterior a :date.',
    'array' => 'El campo :attribute no puede tener más de :max elementos.',
    ],
    'min' => [
        'numeric' => 'El campo :attribute debe ser al menos :min.',
        'string' => 'El campo :attribute debe tener al menos :min caracteres.',
        'after_or_equal' => 'El campo :attribute debe ser una fecha igual o posterior a :date.',
    'array' => 'El campo :attribute debe tener al menos :min elementos.',
    ],
    'numeric' => 'El campo :attribute debe ser un número.',
    'present' => 'El campo :attribute debe estar presente.',
    'regex' => 'El formato de :attribute no es válido.',
    'required' => 'El campo :attribute es obligatorio.',
    'required_if' => 'El campo :attribute es obligatorio.',
    'required_with' => 'El campo :attribute es obligatorio.',
    'string' => 'El campo :attribute debe ser texto.',
    'unique' => 'El valor de :attribute ya existe.',

    /*
    |--------------------------------------------------------------------------
    | Nombres de los campos
    |--------------------------------------------------------------------------
    */

    'attributes' => [
        'data.attributes.cardNumber' => 'carné',
        'data.attributes.firstName' => 'nombre',
        'data.attributes.lastName' => 'apellidos',
        'data.attributes.password' => 'contraseña',
        'data.relationships.rank.data.type' => 'tipo de la jerarquía',
        'data.relationships.rank.data.id' => 'jerarquía',
        'data.attributes.value' => 'valor',
        'data.attributes.refreshToken' => 'token de renovación',
        'data.attributes.deviceName' => 'nombre del dispositivo',
        'photo' => 'foto',
        'icon' => 'icono',
        'apk' => 'APK',
        'versionName' => 'nombre de la versión',
        'versionCode' => 'código de la versión',
        'notes' => 'novedades',
        'data.attributes.childFirstName' => 'nombre del niño',
        'data.attributes.childLastName' => 'apellidos del niño',
        'data.attributes.childCardNumber' => 'carné del niño',
        'data.attributes.startsOn' => 'fecha de inicio',
        'data.attributes.endsOn' => 'fecha de fin',
        'data.attributes.status' => 'estado',
        'data.attributes.type' => 'tipo',
    ],

];
