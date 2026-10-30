<?php

namespace App\Serializers;

class ItineraryChiefSerializer extends RoleSerializer
{
    public function type(): string
    {
        return 'itinerary-chiefs';
    }

    public function toOneRelationships(): array
    {
        return parent::toOneRelationships() + ['itinerary' => ['itineraries', 'itinerary_id', 'itinerary']];
    }
}
