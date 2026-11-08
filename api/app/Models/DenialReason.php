<?php

namespace App\Models;

/**
 * Motivo de denegación de una solicitud (de Entidad, de itinerario o de las dos).
 */
class DenialReason extends Nomenclator
{
    protected $fillable = ['name', 'description', 'observation', 'active', 'application_type'];
}
