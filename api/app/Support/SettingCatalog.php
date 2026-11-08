<?php

namespace App\Support;

/**
 * Ajustes de la app (docs/11 §11.38, §11.40 y §11.44): un solo nivel, para toda
 * la app, todos los usuarios y todos los teléfonos. Solo el Administrador los
 * cambia. La lista es fija (está en el código); en la base de datos solo se
 * guardan los valores cambiados (tabla settings).
 *
 * Nombres cortos, sin artículos ni preposiciones. Tipos:
 * - duracion: «10min», «12hor30min» (seg min hor dia sem mes ano);
 * - distancia: «100m», «1km200m»;
 * - velocidad: «10km/hor»;
 * - entero: número entero (con su unidad en «unit», si la tiene).
 */
final class SettingCatalog
{
    public const TYPE_DURATION = 'duracion';
    public const TYPE_DISTANCE = 'distancia';
    public const TYPE_SPEED = 'velocidad';
    public const TYPE_INTEGER = 'entero';

    /** Grupos, en el orden en que se muestran. */
    public const GROUPS = [
        'general' => 'Generales',
        'estado_trabajador' => 'Estado trabajador',
        'estado_viaje' => 'Estado viaje',
        'notificaciones' => 'Notificaciones',
        'sincronizacion' => 'Sincronización',
        'contrasenas' => 'Contraseñas',
        'acceso' => 'Acceso',
        'olvide' => 'Olvidé algo',
        'conversaciones' => 'Conversaciones',
        'archivos' => 'Archivos',
        'hijos' => 'Hijos',
    ];

    /**
     * clave => [grupo, nombre, tipo, valor por defecto, mínimo, máximo, descripción, unidad (enteros)].
     * Mínimo y máximo con el mismo formato que el valor (texto con unidades o entero).
     */
    public const SETTINGS = [
        // Generales
        'radio_parada' => ['general', 'Radio parada', self::TYPE_DISTANCE, '100m', '10m', '2km',
            'Distancia a una parada dentro de la cual se está en ella (trabajador y vehículo).'],
        'anticipacion_viaje' => ['general', 'Anticipación viaje', self::TYPE_DURATION, '10min', '1min', '3hor',
            'Antes de la salida: recordatorio de activar la ubicación e inicio del cálculo del estado del trabajador.'],
        'minimo_confirmaciones' => ['general', 'Mínimo confirmaciones', self::TYPE_INTEGER, 3, 1, 50,
            'Trabajadores o teléfonos que deben coincidir para cambiar el estado del viaje o del vehículo.'],

        // Estado del trabajador (se calcula en el teléfono)
        'velocidad_humana' => ['estado_trabajador', 'Velocidad humana', self::TYPE_SPEED, '10km/hor', '1km/hor', '40km/hor',
            'Por encima de esta velocidad va en el vehículo (Viajando o Recogido).'],
        'tolerancia_gps' => ['estado_trabajador', 'Tolerancia GPS', self::TYPE_DISTANCE, '20m', '1m', '500m',
            'Diferencia mínima entre dos distancias para considerar que se movió; también, umbral de «misma posición» del sensor.'],
        'distancia_abandono' => ['estado_trabajador', 'Distancia abandono', self::TYPE_DISTANCE, '1km', '100m', '50km',
            'Alejándose a velocidad humana más allá de esta distancia, «No voy a viajar» es definitivo.'],
        'frecuencia_calculo' => ['estado_trabajador', 'Frecuencia cálculo', self::TYPE_DURATION, '10seg', '2seg', '5min',
            'Cada cuánto calcula el teléfono su estado y el del vehículo (y consulta al servidor durante el viaje). Un sensor que no envía nada en 3 cálculos deja de contar.'],
        'calculos_consecutivos' => ['estado_trabajador', 'Cálculos consecutivos', self::TYPE_INTEGER, 6, 1, 100,
            'Cálculos seguidos a velocidad humana en el radio de una parada para quedar Dejado (ida).'],
        'espera_final' => ['estado_trabajador', 'Espera final', self::TYPE_DURATION, '10min', '1min', '5hor',
            'Tras quedar Dormido o Botado sin alejarse, la app deja de calcular y recuerda desactivar el GPS.'],

        // Estado del viaje (lo revisa el servidor)
        'plazo_eliminacion' => ['estado_viaje', 'Plazo eliminación', self::TYPE_DURATION, '5hor', '10min', '7dia',
            'Un viaje que sigue Planificado se elimina pasado este tiempo desde su salida (o su último estado, si es posterior).'],
        'duracion_maxima' => ['estado_viaje', 'Duración máxima', self::TYPE_DURATION, '5hor', '10min', '2dia',
            'Un viaje En ejecución pasa a Terminado pasado este tiempo desde que empezó.'],
        'espera_cierre' => ['estado_viaje', 'Espera cierre', self::TYPE_DURATION, '2hor', '1min', '1dia',
            'Termina el viaje si pasa este tiempo desde el último Dejado (ida) o Recogido (regreso) sin llegar a la parada final.'],

        // Notificaciones
        'detencion_larga' => ['notificaciones', 'Detención larga', self::TYPE_DURATION, '5min', '30seg', '2hor',
            'Se avisa a quienes están En la parada si el vehículo lleva detenido más de este tiempo.'],

        // Sincronización
        'frecuencia_reposo' => ['sincronizacion', 'Frecuencia reposo', self::TYPE_DURATION, '1hor', '1min', '1dia',
            'Consulta al servidor cuando no hay viajes ese día.'],
        'frecuencia_dia_viaje' => ['sincronizacion', 'Frecuencia día viaje', self::TYPE_DURATION, '15min', '10seg', '6hor',
            'Consulta al servidor cuando hay un viaje ese día.'],
        'frecuencia_chat' => ['sincronizacion', 'Frecuencia chat', self::TYPE_DURATION, '5seg', '2seg', '10min',
            'Consulta de la conversación mientras está abierta.'],

        // Contraseñas
        'longitud_contrasena' => ['contrasenas', 'Longitud contraseña', self::TYPE_INTEGER, 8, 6, 64,
            'Cantidad mínima de caracteres.', 'caracteres'],
        'tipos_caracteres' => ['contrasenas', 'Tipos caracteres', self::TYPE_INTEGER, 3, 1, 4,
            'Cuántos tipos hay que combinar: mayúsculas, minúsculas, números y símbolos.'],
        'caducidad_contrasena' => ['contrasenas', 'Caducidad contraseña', self::TYPE_DURATION, '1ano', '30dia', '3ano',
            'Al caducar, hay que cambiarla para seguir.'],
        'historial_contrasenas' => ['contrasenas', 'Historial contraseñas', self::TYPE_INTEGER, 5, 0, 24,
            'Contraseñas anteriores que no se pueden repetir.'],

        // Acceso
        'validez_acceso' => ['acceso', 'Validez acceso', self::TYPE_DURATION, '30min', '5min', '4hor',
            'Validez del token de acceso; la app lo renueva sola.'],
        'validez_sesion' => ['acceso', 'Validez sesión', self::TYPE_DURATION, '90dia', '1dia', '1ano',
            'Tiempo máximo de una sesión sin volver a entrar.'],
        'reserva_usuario' => ['acceso', 'Reserva usuario', self::TYPE_DURATION, '30dia', '0seg', '1ano',
            'Tiempo durante el que nadie más puede usar un nombre de usuario abandonado.'],

        // Olvidé algo
        'validez_olvide' => ['olvide', 'Validez solicitud', self::TYPE_DURATION, '3dia', '1hor', '1mes',
            'Pasado este tiempo sin resolverse, la solicitud «Olvidé algo» caduca.'],
        'limite_olvide' => ['olvide', 'Solicitudes hora', self::TYPE_INTEGER, 3, 1, 20,
            'Solicitudes «Olvidé algo» por hora desde un mismo teléfono.'],

        // Conversaciones
        'conservacion_conversaciones' => ['conversaciones', 'Conservación conversaciones', self::TYPE_DURATION, '1mes', '1dia', '3ano',
            'Las conversaciones se borran pasado este tiempo desde su último mensaje.'],
        'longitud_mensaje' => ['conversaciones', 'Longitud mensaje', self::TYPE_INTEGER, 1000, 50, 5000,
            'Cantidad máxima de caracteres de un mensaje.', 'caracteres'],

        // Archivos
        'tamano_foto' => ['archivos', 'Tamaño foto', self::TYPE_INTEGER, 2048, 100, 10240,
            'Tamaño máximo de una foto o imagen.', 'KB'],
        'tamano_apk' => ['archivos', 'Tamaño APK', self::TYPE_INTEGER, 150, 10, 500,
            'Tamaño máximo de cada APK de una actualización.', 'MB'],

        // Hijos
        'edad_hijos' => ['hijos', 'Edad hijos', self::TYPE_INTEGER, 16, 0, 25,
            'Edad hasta la que viajan los hijos: hasta el 31 de agosto siguiente al cumpleaños de esa edad.', 'años'],
    ];

    public static function has(string $key): bool
    {
        return isset(self::SETTINGS[$key]);
    }

    /**
     * @return array{key: string, group: string, groupName: string, name: string, type: string, default: string|int, min: string|int, max: string|int, description: string, unit: ?string}
     */
    public static function definition(string $key): array
    {
        $s = self::SETTINGS[$key];

        return [
            'key' => $key,
            'group' => $s[0],
            'groupName' => self::GROUPS[$s[0]],
            'name' => $s[1],
            'type' => $s[2],
            'default' => $s[3],
            'min' => $s[4],
            'max' => $s[5],
            'description' => $s[6],
            'unit' => $s[7] ?? null,
        ];
    }

    /**
     * Valor en la unidad base (segundos, metros, metros por segundo o entero),
     * o null si el texto no es válido para ese tipo.
     */
    public static function base(string $type, $value)
    {
        switch ($type) {
            case self::TYPE_DURATION:
                return Units::seconds(is_string($value) ? $value : null);
            case self::TYPE_DISTANCE:
                return Units::meters(is_string($value) ? $value : null);
            case self::TYPE_SPEED:
                return Units::metersPerSecond(is_string($value) ? $value : null);
            default:
                if (is_int($value)) {
                    return $value;
                }

                return is_string($value) && preg_match('/^-?\d{1,9}$/', trim($value)) ? (int) trim($value) : null;
        }
    }
}
