<?php

namespace Database\Seeders;

use App\Models\SettingDefinition;
use App\Models\SettingOption;
use Illuminate\Database\Seeder;

/**
 * Ajustes de docs/06-ajustes.md.
 */
class SettingDefinitionSeeder extends Seeder
{
    const ADMIN = 'administrator';
    const TRANSPORT_CHIEF = 'transport_chief';

    const TEMPLATE_DEPARTURE = 'Salida {fecha_salida} a las {hora_salida} desde {punto_salida}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}. Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.';
    const TEMPLATE_RETURN = 'Regreso {fecha_regreso} a las {hora_regreso} desde {punto_regreso}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}.';
    const TEMPLATE_STOP = 'El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la tuya.';
    const TEMPLATE_CHANGE = 'Cambió tu viaje de {itinerario} del {fecha_salida}: {cambios}.';
    const TEMPLATE_CANCEL = 'Se canceló tu viaje de {itinerario} del {fecha_salida}.';

    public function run()
    {
        foreach ($this->globalSettings() as $setting) {
            $this->save($setting + ['user_overridable' => false]);
        }

        foreach ($this->userSettings() as $setting) {
            $this->save($setting + ['editable_by' => self::ADMIN, 'user_overridable' => true]);
        }
    }

    private function globalSettings(): array
    {
        return [
            $this->integer('child_max_age', 'Edad máxima de los hijos para viajar', 16, 0, 25, self::TRANSPORT_CHIEF,
                'Tienen derecho hasta el 31 de agosto siguiente al cumpleaños de esta edad.'),
            $this->integer('inactivity_days', 'Días sin viajar para la baja automática', 30, 1, 365, self::TRANSPORT_CHIEF),
            $this->integer('inactivity_warning_days', 'Días de aviso previo a la baja por inactividad', 5, 0, 30, self::TRANSPORT_CHIEF),
            $this->integer('conversation_retention_days', 'Días de conservación de las conversaciones', 30, 1, 365, self::ADMIN,
                'Se cuentan desde el último mensaje.'),
            $this->integer('trip_auto_complete_delay_minutes', 'Minutos tras el regreso para marcar el viaje como realizado', 0, 0, 1440, self::ADMIN),
            $this->integer('stop_detection_radius_m', 'Radio de detección de paradas (m)', 100, 20, 1000, self::ADMIN),
            $this->integer('sensor_outlier_distance_m', 'Distancia para descartar un sensor (m)', 300, 50, 5000, self::ADMIN),
            $this->integer('sensor_stale_seconds', 'Segundos sin enviar para dejar de contar un sensor', 60, 10, 600, self::ADMIN),
            $this->integer('auto_boarding_distance_m', 'Distancia máxima al vehículo para la subida automática (m)', 50, 10, 500, self::ADMIN),
            $this->integer('auto_boarding_samples', 'Posiciones seguidas necesarias para la subida automática', 3, 2, 20, self::ADMIN),
            $this->integer('boarding_pass_ttl_seconds', 'Validez del código QR de subida (s)', 120, 30, 3600, self::ADMIN),
            $this->integer('access_token_ttl_minutes', 'Validez del token de acceso (min)', 30, 5, 240, self::ADMIN),
            $this->integer('refresh_token_ttl_days', 'Validez del token de renovación (días)', 90, 1, 365, self::ADMIN),
            $this->integer('photo_max_kb', 'Tamaño máximo de la foto de perfil (KB)', 2048, 100, 10240, self::ADMIN),
            $this->integer('rank_icon_max_kb', 'Tamaño máximo del icono de jerarquía (KB)', 512, 50, 2048, self::ADMIN),
            $this->integer('message_max_length', 'Longitud máxima de un mensaje de chat', 1000, 50, 5000, self::ADMIN),
            $this->integer('min_foreground_poll_seconds', 'Frecuencia mínima de consulta con la app abierta (s)', 5, 1, 60, self::ADMIN),
            $this->integer('min_background_poll_minutes', 'Frecuencia mínima de sincronización en segundo plano (min)', 30, 15, 1440, self::ADMIN),
            $this->integer('min_location_interval_seconds', 'Frecuencia mínima de envío de ubicación (s)', 5, 1, 60, self::ADMIN),
            $this->integer('min_in_trip_background_poll_seconds', 'Frecuencia mínima en segundo plano durante un recorrido (s)', 30, 10, 600, self::ADMIN),
        ];
    }

    private function userSettings(): array
    {
        $settings = [];

        foreach (['departure' => ['salida', '14:00', 0, self::TEMPLATE_DEPARTURE], 'return' => ['regreso', '23:00', 1, self::TEMPLATE_RETURN]] as $prefix => list($label, $fixedTime, $daysBefore, $template)) {
            $settings[] = $this->option("{$prefix}_notice_mode", "Forma del aviso de {$label}", 'relative', [
                'relative' => 'Tiempo antes',
                'fixed' => 'Hora fija',
            ]);
            $settings[] = $this->integer("{$prefix}_notice_minutes_before", "Minutos antes del aviso de {$label}", 60, 0, 1440);
            $settings[] = $this->time("{$prefix}_notice_fixed_time", "Hora fija del aviso de {$label}", $fixedTime);
            $settings[] = $this->integer("{$prefix}_notice_fixed_days_before", "Días antes de la hora fija del aviso de {$label}", $daysBefore, 0, 7);
            $settings[] = $this->option("{$prefix}_notice_fallback", "Si la hora fija del aviso de {$label} no sirve", 'default', [
                'default' => 'Avisar 1 hora antes',
                'none' => 'No avisar',
            ]);
            $settings[] = $this->text("{$prefix}_notice_template", "Texto del aviso de {$label}", $template);
        }

        return array_merge($settings, [
            $this->option('stop_notice_scope', 'Avisos de paso por paradas', 'previous', [
                'none' => 'Ninguna',
                'previous' => 'Solo la anterior a la mía',
                'all' => 'Todas las anteriores',
            ]),
            $this->boolean('stop_notice_after_boarding', 'Seguir avisando después de subir', false),
            $this->text('stop_notice_template', 'Texto del aviso de paso por parada', self::TEMPLATE_STOP),
            $this->text('change_notice_template', 'Texto del aviso de cambio', self::TEMPLATE_CHANGE),
            $this->text('cancel_notice_template', 'Texto del aviso de cancelación', self::TEMPLATE_CANCEL),
            $this->boolean('notify_during_absence', 'Recibir avisos de viaje durante una ausencia', false),
            $this->option('trip_view', 'Vista del recorrido', 'timeline', [
                'map' => 'Mapa',
                'timeline' => 'Línea con hitos',
            ]),
            $this->boolean('tts_enabled', 'Voz durante el recorrido', true),
            $this->boolean('share_location', 'Compartir ubicación como sensor', false),
            $this->integer('location_interval_seconds', 'Frecuencia de envío de ubicación (s)', 10, null, 600, null, null, 'min_location_interval_seconds'),
            $this->boolean('background_sync_enabled', 'Sincronización en segundo plano', true),
            $this->integer('trips_poll_foreground_seconds', 'Viajes: consulta con la app abierta (s)', 60, null, 3600, null, null, 'min_foreground_poll_seconds'),
            $this->integer('trips_poll_background_minutes', 'Viajes: consulta en segundo plano (min)', 30, null, 1440, null, null, 'min_background_poll_minutes'),
            $this->integer('tracking_poll_foreground_seconds', 'Recorrido: consulta con la app abierta (s)', 10, null, 600, null, null, 'min_foreground_poll_seconds'),
            $this->integer('tracking_poll_background_seconds', 'Recorrido: consulta en segundo plano (s)', 60, null, 3600, null, null, 'min_in_trip_background_poll_seconds'),
            $this->integer('trip_chat_poll_foreground_seconds', 'Chat del viaje: consulta con la app abierta (s)', 5, null, 600, null, null, 'min_foreground_poll_seconds'),
            $this->integer('trip_chat_poll_background_minutes', 'Chat del viaje: consulta en segundo plano (min)', 30, null, 1440, null, null, 'min_background_poll_minutes'),
            $this->integer('conversations_poll_foreground_seconds', 'Conversaciones: consulta con la app abierta (s)', 10, null, 600, null, null, 'min_foreground_poll_seconds'),
            $this->integer('conversations_poll_background_minutes', 'Conversaciones: consulta en segundo plano (min)', 30, null, 1440, null, null, 'min_background_poll_minutes'),
            $this->integer('notices_poll_foreground_seconds', 'Solicitudes y avisos: consulta con la app abierta (s)', 60, null, 3600, null, null, 'min_foreground_poll_seconds'),
            $this->integer('notices_poll_background_minutes', 'Solicitudes y avisos: consulta en segundo plano (min)', 30, null, 1440, null, null, 'min_background_poll_minutes'),
        ]);
    }

    private function integer(string $key, string $name, int $default, ?int $min, ?int $max, ?string $editableBy = null, ?string $description = null, ?string $minKey = null): array
    {
        return [
            'key' => $key, 'name' => $name, 'description' => $description, 'value_type' => SettingDefinition::TYPE_INTEGER,
            'default_value' => (string) $default, 'min_value' => $min, 'max_value' => $max, 'editable_by' => $editableBy,
            'min_key' => $minKey,
        ];
    }

    private function boolean(string $key, string $name, bool $default): array
    {
        return ['key' => $key, 'name' => $name, 'value_type' => SettingDefinition::TYPE_BOOLEAN, 'default_value' => $default ? '1' : '0'];
    }

    private function time(string $key, string $name, string $default): array
    {
        return ['key' => $key, 'name' => $name, 'value_type' => SettingDefinition::TYPE_TIME, 'default_value' => $default];
    }

    private function text(string $key, string $name, string $default): array
    {
        return [
            'key' => $key, 'name' => $name, 'value_type' => SettingDefinition::TYPE_STRING, 'default_value' => $default,
            'min_value' => 1, 'max_value' => 500,
        ];
    }

    private function option(string $key, string $name, string $default, array $options): array
    {
        return [
            'key' => $key, 'name' => $name, 'value_type' => SettingDefinition::TYPE_OPTION, 'default_value' => $default,
            'options' => $options,
        ];
    }

    private function save(array $setting): void
    {
        $options = isset($setting['options']) ? $setting['options'] : [];
        $minKey = isset($setting['min_key']) ? $setting['min_key'] : null;
        unset($setting['options'], $setting['min_key']);

        if ($minKey) {
            $setting['min_setting_definition_id'] = SettingDefinition::where('key', $minKey)->value('id');
        }

        $definition = SettingDefinition::withTrashed()->updateOrCreate(['key' => $setting['key']], $setting + [
            'description' => null, 'min_value' => null, 'max_value' => null, 'editable_by' => null,
        ]);

        foreach ($options as $value => $name) {
            SettingOption::withTrashed()->updateOrCreate(
                ['setting_definition_id' => $definition->id, 'value' => $value],
                ['name' => $name]
            );
        }
    }
}
