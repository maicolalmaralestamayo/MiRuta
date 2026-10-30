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
        App\Models\AppVersion::class => App\Serializers\AppVersionSerializer::class,
        App\Models\Application::class => App\Serializers\ApplicationSerializer::class,
        App\Models\Child::class => App\Serializers\ChildSerializer::class,
        App\Models\Notice::class => App\Serializers\NoticeSerializer::class,
        App\Models\AbsenceType::class => App\Serializers\AbsenceTypeSerializer::class,
        App\Models\ConversationTopic::class => App\Serializers\ConversationTopicSerializer::class,
        App\Models\Conversation::class => App\Serializers\ConversationSerializer::class,
        App\Models\ConversationMessage::class => App\Serializers\ConversationMessageSerializer::class,
        App\Models\TripMessage::class => App\Serializers\TripMessageSerializer::class,
        App\Models\Driver::class => App\Serializers\DriverSerializer::class,
        App\Models\Itinerary::class => App\Serializers\ItinerarySerializer::class,
        App\Models\ItineraryChief::class => App\Serializers\ItineraryChiefSerializer::class,
        App\Models\ItineraryStop::class => App\Serializers\ItineraryStopSerializer::class,
        App\Models\PasswordReset::class => App\Serializers\PasswordResetSerializer::class,
        App\Models\Rank::class => App\Serializers\RankSerializer::class,
        App\Models\SettingDefinition::class => App\Serializers\SettingDefinitionSerializer::class,
        App\Models\Stop::class => App\Serializers\StopSerializer::class,
        App\Models\Trip::class => App\Serializers\TripSerializer::class,
        App\Models\TripBoarding::class => App\Serializers\TripBoardingSerializer::class,
        App\Models\TripCompletion::class => App\Serializers\TripCompletionSerializer::class,
        App\Models\TripLeg::class => App\Serializers\TripLegSerializer::class,
        App\Models\TripPosition::class => App\Serializers\TripPositionSerializer::class,
        App\Models\TripStopPass::class => App\Serializers\TripStopPassSerializer::class,
        App\Models\TransportChief::class => App\Serializers\TransportChiefSerializer::class,
        App\Models\Vehicle::class => App\Serializers\VehicleSerializer::class,
        App\Models\VehicleType::class => App\Serializers\VehicleTypeSerializer::class,
        App\Models\Worker::class => App\Serializers\WorkerSerializer::class,
    ],

    /*
    |--------------------------------------------------------------------------
    | Operaciones atómicas de otros recursos
    |--------------------------------------------------------------------------
    |
    | "op:tipo" => [clase, método]. El método recibe (data, request, pointer)
    | y devuelve el modelo creado o modificado.
    |
    */

    'operations' => [
        'add:trip-positions' => [App\Http\Controllers\TripPositionController::class, 'createFromOperation'],
    ],

];
