<?php

namespace App\Models;

/**
 * Tipo de vehículo: asientos y pasajeros de pie; el total se calcula.
 */
class VehicleType extends Nomenclator
{
    protected $fillable = ['name', 'description', 'observation', 'active', 'seats', 'standing'];

    protected $casts = ['active' => 'boolean', 'seats' => 'integer', 'standing' => 'integer'];

    public function capacity(): int
    {
        return (int) $this->seats + (int) $this->standing;
    }
}
