<?php

use App\Models;
use App\Serializers;

return [

    /*
    |--------------------------------------------------------------------------
    | Serializadores
    |--------------------------------------------------------------------------
    |
    | Qué serializador convierte cada modelo en un recurso JSON:API. Los
    | nomencladores usan el mismo serializador con su tipo.
    |
    */

    'serializers' => [
        Models\User::class => Serializers\UserSerializer::class,
        Models\Worker::class => Serializers\WorkerSerializer::class,
        Models\Entity::class => Serializers\EntitySerializer::class,
        Models\Itinerary::class => Serializers\ItinerarySerializer::class,
        Models\Stop::class => Serializers\StopSerializer::class,
        Models\ItineraryStop::class => Serializers\ItineraryStopSerializer::class,
        Models\Application::class => Serializers\ApplicationSerializer::class,
        Models\Absence::class => Serializers\AbsenceSerializer::class,
        Models\Child::class => Serializers\ChildSerializer::class,
        Models\Trip::class => Serializers\TripSerializer::class,
        Models\TripPassenger::class => Serializers\TripPassengerSerializer::class,
        Models\Conversation::class => Serializers\ConversationSerializer::class,
        Models\ConversationMessage::class => Serializers\ConversationMessageSerializer::class,
        Models\AppVersion::class => Serializers\AppVersionSerializer::class,
        Models\AccessRecovery::class => Serializers\AccessRecoverySerializer::class,
        Models\Installation::class => Serializers\InstallationSerializer::class,
        Models\VehicleType::class => [Serializers\NomenclatorSerializer::class, 'vehicle-types'],
        Models\AbsenceType::class => [Serializers\NomenclatorSerializer::class, 'absence-types'],
        Models\ConversationTopic::class => [Serializers\NomenclatorSerializer::class, 'conversation-topics'],
        Models\DenialReason::class => [Serializers\NomenclatorSerializer::class, 'denial-reasons'],
        Models\DetentionCause::class => [Serializers\NomenclatorSerializer::class, 'detention-causes'],
    ],

];
