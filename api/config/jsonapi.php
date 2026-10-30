<?php

return [

    /*
    |--------------------------------------------------------------------------
    | Serializadores
    |--------------------------------------------------------------------------
    |
    | Qué serializador convierte cada modelo en un recurso JSON:API.
    |
    */

    'serializers' => [
        App\Models\Rank::class => App\Serializers\RankSerializer::class,
        App\Models\SettingDefinition::class => App\Serializers\SettingDefinitionSerializer::class,
        App\Models\Worker::class => App\Serializers\WorkerSerializer::class,
    ],

];
