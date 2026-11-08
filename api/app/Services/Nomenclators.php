<?php

namespace App\Services;

use App\Models;
use Illuminate\Support\Facades\DB;

/**
 * Nomencladores (solo el Administrador los cambia; todos los consultan). Lo
 * que está en uso no se elimina: se propone desactivarlo (docs/11 §11.29).
 */
class Nomenclators
{
    /** tipo JSON:API => [modelo, nombre en singular, [[tabla, columna] donde se usa]] */
    public const TYPES = [
        'vehicle-types' => [Models\VehicleType::class, 'tipo de vehículo', [['trips', 'vehicle_type_id']]],
        'absence-types' => [Models\AbsenceType::class, 'tipo de ausencia', [['absences', 'absence_type_id']]],
        'conversation-topics' => [Models\ConversationTopic::class, 'motivo de conversación', [['conversations', 'conversation_topic_id']]],
        'denial-reasons' => [Models\DenialReason::class, 'motivo de denegación', [['applications', 'denial_reason_id']]],
        'detention-causes' => [Models\DetentionCause::class, 'causa de detención', [['trips', 'detention_cause_id']]],
    ];

    public function usageCount(string $type, int $id): int
    {
        $count = 0;

        foreach (self::TYPES[$type][2] ?? [] as [$table, $column]) {
            $count += DB::table($table)->where($column, $id)->count();
        }

        return $count;
    }
}
