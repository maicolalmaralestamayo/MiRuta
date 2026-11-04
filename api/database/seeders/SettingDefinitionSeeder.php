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
    /** Solo el Administrador, para toda la app. */
    const APP = 'app';

    /** El valor de la app (settings.app) y el de cada Entidad (settings.entity). */
    const ENTITY = 'entity';

    const TEMPLATE_DEPARTURE = 'Viaje de ida: {fecha_salida} a las {hora_salida} desde {punto_salida}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}. Viaje de regreso: {fecha_regreso} a las {hora_regreso} desde {punto_regreso}.';
    const TEMPLATE_RETURN = 'Viaje de regreso: {fecha_regreso} a las {hora_regreso} desde {punto_regreso}. {tipo} {matricula}, chofer {chofer}, capacidad {capacidad}.';
    const TEMPLATE_STOP = 'El transporte pasó por {parada} a las {hora}. Faltan {paradas_restantes} paradas para la suya.';
    const TEMPLATE_CHANGE = 'Cambió su viaje de {itinerario} del {fecha_salida}: {cambios}.';
    const TEMPLATE_CANCEL = 'Se canceló su viaje de {itinerario} del {fecha_salida}.';

    public function run()
    {
        // Ajustes que ya no existen (versiones anteriores).
        SettingDefinition::whereIn('key', ['password_forbid_personal_data', 'password_forbid_common', 'password_expiry_warning_days',
            'activation_code_ttl_days', 'rank_icon_max_kb', 'boarding_pass_ttl_seconds'])->delete();

        foreach ($this->appSettings() as $setting) {
            $this->save($setting + ['level' => self::APP, 'user_overridable' => false]);
        }

        foreach ($this->entitySettings() as $setting) {
            $this->save($setting + ['level' => self::ENTITY, 'user_overridable' => false]);
        }

        foreach ($this->userSettings() as $setting) {
            $this->save($setting + ['level' => self::ENTITY, 'user_overridable' => true]);
        }
    }

    private function appSettings(): array
    {
        return [
            // Caducidades
            $this->integer('conversation_retention_days', 'Días de conservación de las conversaciones', 30, 1, 365,
                'Se cuentan desde el último mensaje.'),
            $this->integer('guest_conversation_retention_days', 'Días de conservación de las conversaciones sin cuenta', 30, 1, 365,
                'Se cuentan desde el último mensaje.'),
            $this->integer('trip_chat_retention_days', 'Días de conservación del chat de un viaje', 0, 0, 365,
                'Desde el regreso; 0 = se borra en cuanto el viaje termina.'),
            $this->integer('read_notice_retention_days', 'Días de conservación de los avisos leídos', 90, 1, 3650,
                'Pasado ese plazo los avisos leídos se borran.'),
            $this->integer('access_recovery_ttl_hours', 'Validez de una solicitud "Olvidé algo" (horas)', 72, 1, 720,
                'Pasado ese plazo sin aprobarse, la solicitud caduca.'),
            $this->integer('access_token_ttl_minutes', 'Validez del token de acceso (min)', 30, 5, 240,
                'La app lo renueva sola sin pedir la contraseña.'),
            $this->integer('refresh_token_ttl_days', 'Validez del token de renovación (días)', 90, 1, 365,
                'Tiempo máximo de una sesión sin volver a entrar.'),
            $this->integer('username_reuse_block_days', 'Días de reserva de un nombre de usuario abandonado', 30, 0, 365,
                'Nadie más puede usarlo durante ese tiempo.'),
            // Contraseñas
            $this->integer('password_min_length', 'Longitud mínima de la contraseña', 8, 6, 64,
                'Cantidad mínima de caracteres.'),
            $this->integer('password_required_classes', 'Tipos de carácter exigidos en la contraseña', 3, 1, 4,
                'De mayúsculas, minúsculas, números y símbolos.'),
            $this->integer('password_expiry_days', 'Caducidad de la contraseña (días)', 365, 30, 1095,
                'Al caducar, hay que cambiarla para seguir.'),
            $this->integer('password_history_count', 'Contraseñas anteriores que no se pueden repetir', 5, 0, 24,
                'Evita volver a poner las últimas contraseñas.'),
            $this->integer('remember_password_max_days', 'Máximo de días para recordar la contraseña', 30, 1, 365,
                'Límite del ajuste "Días para recordar la contraseña".'),
            // Límites contra el abuso
            $this->integer('access_recovery_max_per_hour', 'Solicitudes "Olvidé algo" por hora desde un teléfono', 3, 1, 20,
                'Evita el abuso desde un mismo teléfono.'),
            $this->integer('guest_messages_max_per_hour', 'Mensajes por hora sin cuenta desde un teléfono', 10, 1, 100,
                'Evita el abuso desde un mismo teléfono.'),
            // Vehículos
            $this->text('plate_letters', 'Letras permitidas en las matrículas', 'B,P,T',
                'Separadas por comas; la matrícula es una letra y 6 dígitos.'),
            // Mapa
            $this->text('map_tiles_url', 'Dirección de las imágenes del mapa', '/tiles/{z}/{x}/{y}.png',
                'Del servidor de mapas propio; relativa a la dirección del servidor.'),
            // Recorrido
            $this->integer('trip_auto_complete_delay_minutes', 'Minutos tras el regreso para dar el viaje por realizado', 0, 0, 1440,
                'Si nadie lo marca antes como realizado.'),
            $this->integer('stop_detection_radius_m', 'Radio de detección de paradas (m)', 100, 20, 1000,
                'Distancia a la que se considera que el vehículo está en la parada.'),
            $this->integer('sensor_outlier_distance_m', 'Distancia para descartar un sensor (m)', 300, 50, 5000,
                'Un teléfono tan alejado de los demás no se tiene en cuenta.'),
            $this->integer('sensor_stale_seconds', 'Segundos sin enviar para dejar de contar un sensor', 60, 10, 600,
                'Un teléfono que deja de enviar su ubicación deja de contar.'),
            $this->integer('auto_boarding_distance_m', 'Distancia al vehículo para la subida automática (m)', 50, 10, 500,
                'Cerca de esa distancia se registra la subida sola.'),
            $this->integer('auto_boarding_samples', 'Posiciones seguidas para la subida automática', 3, 2, 20,
                'Cuántas veces seguidas tiene que estar cerca.'),
            // Tamaños
            $this->integer('photo_max_kb', 'Tamaño máximo de una foto o imagen (KB)', 2048, 100, 10240,
                'Fotos de perfil y de los hijos, e imágenes de Entidades, itinerarios y paradas.'),
            $this->integer('app_max_mb', 'Tamaño máximo del APK de una actualización (MB)', 150, 10, 500,
                'Los APK más grandes se rechazan.'),
            $this->integer('message_max_length', 'Longitud máxima de un mensaje de chat', 1000, 50, 5000,
                'Cantidad máxima de caracteres por mensaje.'),
            // Mínimos y máximos de frecuencia
            $this->integer('min_foreground_poll_seconds', 'Frecuencia mínima de consulta con la app abierta (s)', 5, 1, 60,
                'Ningún usuario puede consultar más a menudo.'),
            $this->integer('min_background_poll_minutes', 'Frecuencia mínima en segundo plano (min)', 30, 15, 1440,
                'Ningún usuario puede sincronizar más a menudo.'),
            $this->integer('min_location_interval_seconds', 'Frecuencia mínima de envío de ubicación (s)', 5, 1, 60,
                'Ningún sensor puede enviar más a menudo.'),
            $this->integer('min_in_trip_background_poll_seconds', 'Frecuencia mínima en segundo plano durante un recorrido (s)', 30, 10, 600,
                'Ningún usuario puede consultar más a menudo durante el recorrido.'),
        ];
    }

    private function entitySettings(): array
    {
        return [
            $this->integer('child_max_age', 'Edad máxima de los hijos para viajar', 16, 0, 25,
                'Hasta el 31 de agosto siguiente al cumpleaños de esa edad.'),
            $this->integer('inactivity_days', 'Días sin viajar para la baja automática', 30, 1, 365,
                'Pasados esos días sin viajar, sale del itinerario.'),
            $this->integer('inactivity_warning_days', 'Días de aviso previo a la baja por inactividad', 5, 0, 30,
                'Se avisa antes de dar la baja.'),
            $this->integer('trip_delay_tolerance_minutes', 'Minutos de tolerancia antes de dar un viaje por atrasado', 5, 0, 120,
                'Si el viaje no ha comenzado pasado ese tiempo, está atrasado.'),
            $this->integer('stop_min_dwell_seconds', 'Segundos mínimos detenido en una parada', 15, 0, 600,
                'Si se detiene menos, se considera que no paró.'),
            $this->integer('stop_pass_speed_kmh', 'Velocidad a partir de la cual no se detuvo (km/h)', 5, 1, 60,
                'Si no baja de esa velocidad en la parada, no paró.'),
            $this->integer('route_deviation_m', 'Distancia al recorrido de referencia para un desvío (m)', 300, 50, 5000,
                'Si se aleja más, se avisa del desvío.'),
        ];
    }

    private function userSettings(): array
    {
        $settings = [];

        foreach (['departure' => ['viaje de ida', '14:00', 0, self::TEMPLATE_DEPARTURE], 'return' => ['viaje de regreso', '23:00', 1, self::TEMPLATE_RETURN]] as $prefix => list($label, $fixedTime, $daysBefore, $template)) {
            $settings[] = $this->option("{$prefix}_notice_mode", "Forma del aviso de {$label}", 'relative', [
                'relative' => 'Tiempo antes',
                'fixed' => 'Hora fija',
            ], 'Avisar un tiempo antes o a una hora fija.');
            $settings[] = $this->integer("{$prefix}_notice_minutes_before", "Minutos antes del aviso de {$label}", 60, 0, 1440, null, null,
                'Con la forma "Tiempo antes".');
            $settings[] = $this->time("{$prefix}_notice_fixed_time", "Hora fija del aviso de {$label}", $fixedTime,
                'Con la forma "Hora fija".');
            $settings[] = $this->integer("{$prefix}_notice_fixed_days_before", "Días antes de la hora fija del aviso de {$label}", $daysBefore, 0, 7,
                '0 = el mismo día del viaje.');
            $settings[] = $this->option("{$prefix}_notice_fallback", "Si la hora fija del aviso de {$label} ya pasó", 'default', [
                'default' => 'Avisar 1 hora antes',
                'none' => 'No avisar',
            ], 'Qué hacer si el viaje se planifica después de esa hora.');
            $settings[] = $this->text("{$prefix}_notice_template", "Texto del aviso de {$label}", $template,
                'Las palabras entre llaves se sustituyen por los datos del viaje.');
        }

        return array_merge($settings, [
            $this->option('stop_notice_scope', 'Avisos de paso por paradas', 'previous', [
                'none' => 'Ninguna',
                'previous' => 'Solo la anterior a la mía',
                'all' => 'Todas las anteriores',
            ], 'De qué paradas anteriores a la suya avisar.'),
            $this->boolean('stop_notice_after_boarding', 'Seguir avisando después de subir', false,
                'Avisos de paradas aunque ya haya subido.'),
            $this->text('stop_notice_template', 'Texto del aviso de paso por parada', self::TEMPLATE_STOP,
                'Las palabras entre llaves se sustituyen por los datos.'),
            $this->text('change_notice_template', 'Texto del aviso de cambio', self::TEMPLATE_CHANGE,
                'Las palabras entre llaves se sustituyen por los datos.'),
            $this->text('cancel_notice_template', 'Texto del aviso de cancelación', self::TEMPLATE_CANCEL,
                'Las palabras entre llaves se sustituyen por los datos.'),
            $this->boolean('notify_during_absence', 'Avisos de viaje durante una ausencia', false,
                'Recibirlos aunque tenga una ausencia aprobada.'),
            $this->boolean('trip_start_notice_enabled', 'Aviso de comienzo del viaje', true,
                'Cuando comienza el viaje de ida o de regreso, a tiempo o con atraso.'),
            $this->boolean('trip_delay_notice_enabled', 'Aviso de viaje atrasado', true,
                'Cuando el viaje no comienza a su hora.'),
            $this->boolean('saturation_notice_enabled', 'Avisos de saturación del transporte', true,
                'Cuando los trabajadores esperados superan la capacidad.'),
            $this->option('saturation_notice_level', 'Avisar cuando el transporte esté', 'overloaded', [
                'overloaded' => 'Sobresaturado (no caben)',
                'saturated' => 'Saturado (van de pie) o sobresaturado',
            ], 'A partir de qué nivel avisar.'),
            $this->option('saturation_notice_scope', 'Avisos de saturación de', 'managed', [
                'own' => 'Mis viajes',
                'managed' => 'Los viajes que gestiono (mi itinerario o mi Entidad)',
            ], 'Qué viajes vigilar.'),
            $this->option('saturation_notice_when', 'Cuándo avisar de la saturación', 'change', [
                'change' => 'Cuando cambia',
                'before' => 'Antes de la salida',
                'both' => 'Las dos',
            ], 'Al cambiar la ocupación, antes de salir o en los dos casos.'),
            $this->integer('saturation_notice_minutes_before', 'Minutos antes de la salida para el aviso de saturación', 120, 0, 1440, null, null,
                'Con "Antes de la salida".'),
            $this->boolean('trip_chat_notice_enabled', 'Avisos de mensajes nuevos en el chat del viaje', true,
                'Notificación al llegar un mensaje.'),
            $this->boolean('conversation_notice_enabled', 'Avisos de mensajes nuevos en las conversaciones', true,
                'Notificación al llegar una respuesta.'),
            $this->integer('password_expiry_notice_days', 'Días de aviso antes de que caduque la contraseña', 15, 0, 60, null, null,
                'Un aviso cada día durante esos días; 0 = sin avisos.'),
            $this->boolean('remember_password', 'Recordar contraseña', true,
                'No pedirla al abrir la app durante los días indicados.'),
            $this->integer('remember_password_days', 'Días para recordar la contraseña', 7, 1, 365, null, null,
                'Pasado ese plazo se vuelve a pedir.', 'remember_password_max_days'),
            $this->option('trip_view', 'Vista del recorrido', 'timeline', [
                'map' => 'Mapa',
                'timeline' => 'Línea con hitos',
            ], 'Cómo se abre el recorrido en tiempo real.'),
            $this->boolean('tts_enabled', 'Voz durante el recorrido', true,
                'Anuncia las paradas en voz alta.'),
            $this->boolean('share_location', 'Compartir ubicación como sensor', false,
                'Ayuda a saber dónde va el vehículo.'),
            $this->integer('location_interval_seconds', 'Frecuencia de envío de ubicación (s)', 10, null, 600, null, 'min_location_interval_seconds',
                'Cada cuánto se envía la ubicación durante el recorrido.'),
            $this->boolean('background_sync_enabled', 'Sincronización en segundo plano', true,
                'Consultar viajes, avisos y mensajes con la app cerrada.'),
            $this->integer('update_check_hours', 'Comprobar actualizaciones de la app (h)', 24, 1, 168, null, null,
                'Cada cuánto se busca una versión nueva.'),
            $this->integer('trips_poll_foreground_seconds', 'Viajes: consulta con la app abierta (s)', 60, null, 3600, null, 'min_foreground_poll_seconds',
                'Cada cuánto se actualizan los viajes.'),
            $this->integer('trips_poll_background_minutes', 'Viajes: consulta en segundo plano (min)', 30, null, 1440, null, 'min_background_poll_minutes',
                'Cada cuánto se actualizan con la app cerrada.'),
            $this->integer('tracking_poll_foreground_seconds', 'Recorrido: consulta con la app abierta (s)', 10, null, 600, null, 'min_foreground_poll_seconds',
                'Cada cuánto se actualiza la posición del vehículo.'),
            $this->integer('tracking_poll_background_seconds', 'Recorrido: consulta en segundo plano (s)', 60, null, 3600, null, 'min_in_trip_background_poll_seconds',
                'Con la app cerrada durante el recorrido.'),
            $this->integer('trip_chat_poll_foreground_seconds', 'Chat del viaje: consulta con la app abierta (s)', 5, null, 600, null, 'min_foreground_poll_seconds',
                'Cada cuánto se buscan mensajes nuevos.'),
            $this->integer('trip_chat_poll_background_minutes', 'Chat del viaje: consulta en segundo plano (min)', 30, null, 1440, null, 'min_background_poll_minutes',
                'Con la app cerrada.'),
            $this->integer('conversations_poll_foreground_seconds', 'Conversaciones: consulta con la app abierta (s)', 10, null, 600, null, 'min_foreground_poll_seconds',
                'Cada cuánto se buscan respuestas nuevas.'),
            $this->integer('conversations_poll_background_minutes', 'Conversaciones: consulta en segundo plano (min)', 30, null, 1440, null, 'min_background_poll_minutes',
                'Con la app cerrada.'),
            $this->integer('notices_poll_foreground_seconds', 'Solicitudes y avisos: consulta con la app abierta (s)', 60, null, 3600, null, 'min_foreground_poll_seconds',
                'Cada cuánto se buscan avisos nuevos.'),
            $this->integer('notices_poll_background_minutes', 'Solicitudes y avisos: consulta en segundo plano (min)', 30, null, 1440, null, 'min_background_poll_minutes',
                'Con la app cerrada.'),
        ]);
    }

    /**
     * Ajuste numérico. Admite la descripción en la sexta o en la octava posición
     * (cuando hay un ajuste que fija el mínimo) y un ajuste que fija el máximo.
     */
    private function integer(string $key, string $name, int $default, ?int $min, ?int $max, ?string $description = null, ?string $minKey = null, ?string $longDescription = null, ?string $maxKey = null): array
    {
        return [
            'key' => $key, 'name' => $name, 'description' => $description ?: $longDescription, 'value_type' => SettingDefinition::TYPE_INTEGER,
            'default_value' => (string) $default, 'min_value' => $min, 'max_value' => $max, 'min_key' => $minKey, 'max_key' => $maxKey,
        ];
    }

    private function boolean(string $key, string $name, bool $default, ?string $description = null): array
    {
        return ['key' => $key, 'name' => $name, 'description' => $description, 'value_type' => SettingDefinition::TYPE_BOOLEAN, 'default_value' => $default ? '1' : '0'];
    }

    private function time(string $key, string $name, string $default, ?string $description = null): array
    {
        return ['key' => $key, 'name' => $name, 'description' => $description, 'value_type' => SettingDefinition::TYPE_TIME, 'default_value' => $default];
    }

    private function text(string $key, string $name, string $default, ?string $description = null): array
    {
        return [
            'key' => $key, 'name' => $name, 'description' => $description, 'value_type' => SettingDefinition::TYPE_STRING, 'default_value' => $default,
            'min_value' => 1, 'max_value' => 500,
        ];
    }

    private function option(string $key, string $name, string $default, array $options, ?string $description = null): array
    {
        return [
            'key' => $key, 'name' => $name, 'description' => $description, 'value_type' => SettingDefinition::TYPE_OPTION, 'default_value' => $default,
            'options' => $options,
        ];
    }

    /**
     * Ajustes que se pueden cambiar por itinerario (docs/11 §11.17): los del
     * viaje y el recorrido.
     */
    const ITINERARY_LEVEL = [
        'trip_delay_tolerance_minutes', 'route_deviation_m', 'trip_chat_retention_days', 'trip_auto_complete_delay_minutes',
        'stop_detection_radius_m', 'inactivity_days', 'inactivity_warning_days', 'stop_min_dwell_seconds', 'stop_pass_speed_kmh',
    ];

    /** Y por parada de un itinerario. */
    const STOP_LEVEL = ['stop_min_dwell_seconds', 'stop_pass_speed_kmh'];

    private function save(array $setting): void
    {
        $setting['itinerary_level'] = in_array($setting['key'], self::ITINERARY_LEVEL, true);
        $setting['stop_level'] = in_array($setting['key'], self::STOP_LEVEL, true);
        $options = isset($setting['options']) ? $setting['options'] : [];
        $minKey = isset($setting['min_key']) ? $setting['min_key'] : null;
        $maxKey = isset($setting['max_key']) ? $setting['max_key'] : null;
        unset($setting['options'], $setting['min_key'], $setting['max_key']);

        $setting['min_setting_definition_id'] = $minKey ? SettingDefinition::where('key', $minKey)->value('id') : null;
        $setting['max_setting_definition_id'] = $maxKey ? SettingDefinition::where('key', $maxKey)->value('id') : null;

        $definition = SettingDefinition::withTrashed()->updateOrCreate(['key' => $setting['key']], $setting + [
            'description' => null, 'min_value' => null, 'max_value' => null,
        ]);

        foreach ($options as $value => $name) {
            SettingOption::withTrashed()->updateOrCreate(
                ['setting_definition_id' => $definition->id, 'value' => $value],
                ['name' => $name]
            );
        }
    }
}
