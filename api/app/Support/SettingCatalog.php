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
        'ventana' => 'Ventana viaje',
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
        // Ventana de viaje (docs/11 §11.62) y frecuencias (docs/11 §11.65)
        'anticipacion_viaje' => ['ventana', 'Inicio ventana', self::TYPE_DURATION, '10min', '1min', '3hor',
            'X: la ventana de viaje empieza este tiempo antes de la salida planificada (servicio de ubicación, recordatorio de activar la ubicación e inicio del cálculo del estado del trabajador).'],
        'fin_ventana' => ['ventana', 'Fin ventana', self::TYPE_DURATION, '5min', '0seg', '2hor',
            'Y: la ventana de viaje termina este tiempo después de que el viaje termine para el trabajador (su estado definitivo o el fin del viaje).'],
        'frecuencia_corta' => ['ventana', 'Frecuencia corta', self::TYPE_DURATION, '10seg', '2seg', '5min',
            'Con la app abierta (a la vista o en recientes) y, con la app cerrada, dentro de la ventana de un viaje: cada cuánto el teléfono consulta al servidor (y dentro de la ventana calcula su estado y el del vehículo y los envía en la misma petición). Un sensor que no envía nada en 3 veces este tiempo deja de contar.'],
        'frecuencia_larga' => ['ventana', 'Frecuencia larga', self::TYPE_DURATION, '15min', '15min', '1dia',
            'Solo con la app cerrada y fuera de la ventana de un viaje: cada cuánto el teléfono consulta al servidor, sin GPS (mínimo 15 min, límite de Android).'],

        // Generales
        'radio_parada' => ['general', 'Radio parada', self::TYPE_DISTANCE, '100m', '10m', '2km',
            'A esta distancia o menos de una parada se está En Parada (trabajador) o en la parada (vehículo).'],
        'radio_acercamiento' => ['general', 'Radio acercamiento', self::TYPE_DISTANCE, '300m', '20m', '5km',
            'Entre este radio y el Radio parada, el trabajador está Acercándose a Parada o Alejándose de Parada; a más de él de todas las paradas, Fuera de itinerario.'],
        'minimo_confirmaciones' => ['general', 'Mínimo confirmaciones', self::TYPE_INTEGER, 3, 1, 50,
            'Trabajadores o teléfonos que deben coincidir para cambiar el estado del viaje o del vehículo.'],

        // Estado del trabajador (se calcula en el teléfono; docs/11 §11.67)
        'velocidad_humana' => ['estado_trabajador', 'Velocidad humana', self::TYPE_SPEED, '10km/hor', '1km/hor', '40km/hor',
            'Hasta esta velocidad se va a pie; por encima, en un vehículo.'],
        'tolerancia_gps' => ['estado_trabajador', 'Tolerancia GPS', self::TYPE_DISTANCE, '20m', '1m', '500m',
            'Diferencia mínima entre dos distancias para considerar que se movió; también, umbral de «misma posición» (Detenido).'],
        'calculos_consecutivos' => ['estado_trabajador', 'Cálculos consecutivos', self::TYPE_INTEGER, 3, 1, 100,
            'Cálculos seguidos que confirman una tendencia: acercarse o alejarse de una parada, alejarse a velocidad de vehículo (Viajando) o a velocidad humana (Dejado).'],

        // Estado del viaje (lo revisa el servidor; docs/11 §11.67)
        'plazo_cancelacion' => ['estado_viaje', 'Plazo cancelación', self::TYPE_DURATION, '5hor', '10min', '7dia',
            'Un viaje que sigue Planificado pasa a Cancelado pasado este tiempo desde su salida.'],
        'duracion_maxima' => ['estado_viaje', 'Duración máxima', self::TYPE_DURATION, '5hor', '10min', '2dia',
            'Un viaje En ejecución pasa a Terminado pasado este tiempo desde que empezó.'],
        'espera_cierre' => ['estado_viaje', 'Espera cierre', self::TYPE_DURATION, '2hor', '1min', '1dia',
            'Termina el viaje si pasa este tiempo desde el último Dejado sin llegar a la parada final.'],
        'conservacion_viajes' => ['estado_viaje', 'Conservación viajes', self::TYPE_DURATION, '30dia', '1dia', '3ano',
            'Los viajes Cancelados y Terminados se borran (sin avisar) pasado este tiempo desde su último estado.'],

        // Notificaciones
        'detencion_larga' => ['notificaciones', 'Detención larga', self::TYPE_DURATION, '5min', '30seg', '2hor',
            'Se avisa a quienes están En Parada si el vehículo lleva detenido más de este tiempo.'],

        // Sincronización
        'conservacion_cambios' => ['sincronizacion', 'Conservación cambios', self::TYPE_DURATION, '1mes', '1dia', '1ano',
            'El registro de cambios con que los teléfonos mantienen al día sus datos se borra pasado este tiempo; un teléfono que lleve más sin conectarse vuelve a descargarlo todo.'],
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
