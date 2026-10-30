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
        App\Models\Application::class => App\Serializers\ApplicationSerializer::class,
        App\Models\Child::class => App\Serializers\ChildSerializer::class,
        App\Models\Notice::class => App\Serializers\NoticeSerializer::class,
        App\Models\AbsenceType::class => App\Serializers\AbsenceTypeSerializer::class,
        App\Models\ConversationTopic::class => App\Serializers\ConversationTopicSerializer::class,
        App\Models\Driver::class => App\Serializers\DriverSerializer::class,
        App\Models\Itinerary::class => App\Serializers\ItinerarySerializer::class,
        App\Models\ItineraryChief::class => App\Serializers\ItineraryChiefSerializer::class,
        App\Models\ItineraryStop::class => App\Serializers\ItineraryStopSerializer::class,
        App\Models\Rank::class => App\Serializers\RankSerializer::class,
        App\Models\SettingDefinition::class => App\Serializers\SettingDefinitionSerializer::class,
        App\Models\Stop::class => App\Serializers\StopSerializer::class,
        App\Models\TransportChief::class => App\Serializers\TransportChiefSerializer::class,
        App\Models\Vehicle::class => App\Serializers\VehicleSerializer::class,
        App\Models\VehicleType::class => App\Serializers\VehicleTypeSerializer::class,
        App\Models\Worker::class => App\Serializers\WorkerSerializer::class,
    ],

];
