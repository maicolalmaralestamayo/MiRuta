<?php

use App\Models\QrNonce;
use App\Models\Role;
use App\Models\RolePermission;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripBoardingChild;
use App\Models\TripLeg;
use App\Models\User;
use App\Models\Vehicle;
use App\Models\VehicleType;
use App\Models\Worker;
use App\Services\QrCodes;
use Carbon\Carbon;
use Carbon\CarbonImmutable;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * QR de la persona (docs/11 §11.8 y §11.9): certificado de dispositivo, QR
 * dinámico y QR impreso, subida, gente de fuera, hijos, alta con QR y
 * sincronización sin conexión.
 */
class QrTest extends TestCase
{
    use DatabaseMigrations;

    private $itinerary;
    private $driver;
    private $trip;
    private $member;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 11, 3, 17));
        CarbonImmutable::setTestNow(CarbonImmutable::create(2026, 11, 3, 17));

        $this->itinerary = $this->createItinerary('Ruta Este', 3);
        $this->driver = $this->createDriver();
        $vehicle = Vehicle::create(['entity_id' => $this->defaultEntity()->id, 'vehicle_type_id' => VehicleType::first()->id, 'plate' => 'B1', 'seats' => 10, 'standing_capacity' => 5]);
        $this->trip = Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $vehicle->id, 'driver_id' => $this->driver->id,
            'departs_at' => Carbon::create(2026, 11, 3, 17), 'returns_at' => Carbon::create(2026, 11, 4, 6, 30),
            'status' => Trip::STATUS_CONFIRMED, 'created_by' => $this->createTransportChief()->id,
        ]);
        $this->member = $this->joinItinerary($this->createWorker(), $this->itinerary, 2);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        CarbonImmutable::setTestNow();
        parent::tearDown();
    }

    /*
    |--------------------------------------------------------------------------
    | Ayudas: lo que hace la app en el teléfono
    |--------------------------------------------------------------------------
    */

    /**
     * Clave del teléfono: [clave privada, SPKI DER en base64].
     */
    private function deviceKey(): array
    {
        $key = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']);

        return [$key, QrCodes::pemToBase64(openssl_pkey_get_details($key)['key'])];
    }

    /**
     * Certificado del teléfono de la persona: [certificado, clave privada].
     */
    private function device($who): array
    {
        list($private, $public) = $this->deviceKey();
        $this->jsonApiAs($who, 'POST', '/api/v1/me/qr-devices', ['data' => ['type' => 'qr-devices', 'attributes' => ['publicKey' => $public]]]);
        $this->assertResponseStatus(201);

        return [$this->responseJson()['data']['attributes']['certificate'], $private];
    }

    private function dynamicQr(array $device, int $userId, ?int $time = null, ?string $nonce = null): string
    {
        $payload = json_encode(['u' => $userId, 't' => $time === null ? Carbon::now()->getTimestamp() : $time, 'n' => $nonce ?: bin2hex(random_bytes(8))]);
        openssl_sign($payload, $signature, $device[1], OPENSSL_ALGO_SHA256);

        return 'MR1.'.$device[0].'.'.QrCodes::base64UrlEncode($payload).'.'.QrCodes::base64UrlEncode($signature);
    }

    private function qrOf($worker, ?int $time = null): string
    {
        $user = $this->userOf($worker);

        return $this->dynamicQr($this->device($user), (int) $user->id, $time);
    }

    private function startLeg(string $direction = 'outbound'): string
    {
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/trip-legs', ['data' => ['type' => 'trip-legs',
            'attributes' => ['direction' => $direction],
            'relationships' => ['trip' => ['data' => ['type' => 'trips', 'id' => (string) $this->trip->id]]],
        ]]);
        $this->assertResponseStatus(201);

        return $this->responseJson()['data']['id'];
    }

    private function scan($scanner, string $qr, ?string $legId = null, string $purpose = 'boarding')
    {
        $data = ['type' => 'qr-scans', 'attributes' => ['qr' => $qr, 'purpose' => $purpose]];

        if ($legId) {
            $data['relationships'] = ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]];
        }

        return $this->jsonApiAs($scanner, 'POST', '/api/v1/qr-scans', ['data' => $data]);
    }

    private function boardQr($scanner, string $legId, string $qr, array $attributes = [])
    {
        return $this->jsonApiAs($scanner, 'POST', '/api/v1/trip-boardings', ['data' => ['type' => 'trip-boardings',
            'attributes' => ['method' => 'qr', 'qr' => $qr] + $attributes,
            'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]],
        ]]);
    }

    private function roleWith(string $name, array $permissions): Role
    {
        $this->role('Trabajador');
        $role = Role::create(['name' => $name, 'requestable' => false, 'is_default' => false, 'itinerary_scoped' => false]);

        foreach ($permissions as $operation => $scope) {
            RolePermission::create(['role_id' => $role->id, 'operation' => $operation, 'scope' => $scope]);
        }

        return $role;
    }

    /*
    |--------------------------------------------------------------------------
    | Clave del servidor y certificado
    |--------------------------------------------------------------------------
    */

    public function testClavePublicaYCertificadoDelTelefono()
    {
        $this->jsonApi('GET', '/api/v1/qr-public-key');
        $this->assertResponseOk();
        $serverKey = $this->responseJson()['data']['attributes']['publicKey'];
        $this->assertSame(120, $this->responseJson()['data']['attributes']['clockSkewSeconds']);
        // La clave se crea una vez y se guarda cifrada.
        $this->jsonApi('GET', '/api/v1/qr-public-key');
        $this->assertSame($serverKey, $this->responseJson()['data']['attributes']['publicKey']);
        $stored = \App\Models\ServerKey::first();
        $this->assertStringNotContainsString('PRIVATE KEY', $stored->getRawOriginal('private_key_encrypted'));

        $this->jsonApiAs($this->member, 'POST', '/api/v1/me/qr-devices', ['data' => ['type' => 'qr-devices', 'attributes' => ['publicKey' => 'basura']]]);
        $this->assertJsonApiError(422, 'QR_DEVICE_KEY_INVALID');

        // Una clave RSA no vale: tiene que ser EC P-256.
        $rsa = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_RSA, 'private_key_bits' => 1024]);
        $this->jsonApiAs($this->member, 'POST', '/api/v1/me/qr-devices', ['data' => ['type' => 'qr-devices',
            'attributes' => ['publicKey' => QrCodes::pemToBase64(openssl_pkey_get_details($rsa)['key'])]]]);
        $this->assertJsonApiError(422, 'QR_DEVICE_KEY_INVALID');

        list(, $public) = $this->deviceKey();
        $this->jsonApiAs($this->member, 'POST', '/api/v1/me/qr-devices', ['data' => ['type' => 'qr-devices', 'attributes' => ['publicKey' => $public]]]);
        $this->assertResponseStatus(201);
        $attributes = $this->responseJson()['data']['attributes'];
        list($json, $signature) = explode('.', $attributes['certificate']);
        $certificate = json_decode(QrCodes::base64UrlDecode($json), true);
        $this->assertSame(['u' => (int) $this->member->user_id, 'k' => $public, 'e' => Carbon::now()->addDays(30)->getTimestamp(), 'v' => 1], $certificate);
        // La app comprueba la firma del servidor sobre los bytes JSON con la clave pública.
        $this->assertSame(1, openssl_verify(QrCodes::base64UrlDecode($json), QrCodes::base64UrlDecode($signature), QrCodes::base64ToPem($serverKey), OPENSSL_ALGO_SHA256));
        $this->assertSame($serverKey, $attributes['serverPublicKey']);
    }

    /*
    |--------------------------------------------------------------------------
    | QR dinámico
    |--------------------------------------------------------------------------
    */

    public function testSubidaConQrDinamicoYNonceDeUnSoloUso()
    {
        $legId = $this->startLeg();
        $child = $this->createChild($this->member);
        $qr = $this->qrOf($this->member);
        $this->assertStringStartsWith('MR1.', $qr);
        // El QR no lleva datos personales.
        $this->assertStringNotContainsString((string) $this->member->user->username, base64_decode(strtr(explode('.', $qr)[3], '-_', '+/')));

        $this->scan($this->driver, $qr, $legId);
        $this->assertResponseOk();
        $attributes = $this->responseJson()['data']['attributes'];
        $this->assertSame('dynamic', $attributes['kind']);
        $this->assertSame($this->member->user->fullName(), $attributes['fullName']);
        $this->assertNull($attributes['outsider']);
        $this->assertFalse($attributes['alreadyBoarded']);
        $this->assertSame([(string) $child->id], array_column($attributes['children'], 'id'));

        // Verificar no gasta el código: se gasta al registrar la subida.
        $this->boardQr($this->driver, $legId, $qr, ['childIds' => [$child->id]]);
        $this->assertResponseStatus(201);
        $this->seeJson(['method' => 'qr', 'qrKind' => 'dynamic', 'childIds' => [(string) $child->id], 'childrenCount' => 1]);
        $this->assertSame((string) $this->member->id, $this->responseJson()['data']['relationships']['worker']['data']['id']);

        // El mismo código otra vez: ya se usó.
        $this->scan($this->driver, $qr, $legId);
        $this->assertTrue($this->responseJson()['data']['attributes']['alreadyUsed']);
        $other = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/itinerary-assignments', ['data' => ['type' => 'itinerary-assignments',
            'attributes' => ['qr' => $qr],
            'relationships' => ['itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $this->itinerary->id]], 'stop' => ['data' => ['type' => 'stops', 'id' => (string) $this->itinerary->stops->first()->id]]],
        ]]);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        // Uno nuevo de la misma persona en el mismo trayecto: una sola subida.
        $this->boardQr($this->driver, $legId, $this->qrOf($this->member));
        $this->assertJsonApiError(409, 'ALREADY_BOARDED');

        // Un trabajador no puede escanear la subida de otros.
        $this->boardQr($other, $legId, $this->qrOf($this->member));
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }

    public function testElMismoCodigoNoSeAceptaDosVeces()
    {
        $legId = $this->startLeg();
        $device = $this->device($this->member->user);
        $qr = $this->dynamicQr($device, (int) $this->member->user_id, null, 'a1b2c3d4e5f60718');

        $this->boardQr($this->driver, $legId, $qr);
        $this->assertResponseStatus(201);

        // En otro trayecto (el regreso), el mismo código ya no vale.
        TripLeg::find($legId)->forceFill(['ended_at' => Carbon::now()])->save();
        $returnId = $this->startLeg('return');
        $this->boardQr($this->driver, $returnId, $qr);
        $this->assertJsonApiError(409, 'QR_ALREADY_USED');
        $this->assertSame(1, QrNonce::count());
    }

    public function testQrCaducadoOConFirmaFalsa()
    {
        $legId = $this->startLeg();
        $device = $this->device($this->member->user);
        $userId = (int) $this->member->user_id;

        // ±2 minutos de diferencia entre los teléfonos.
        $this->scan($this->driver, $this->dynamicQr($device, $userId, Carbon::now()->getTimestamp() - 121), $legId);
        $this->assertJsonApiError(422, 'QR_EXPIRED');
        $this->scan($this->driver, $this->dynamicQr($device, $userId, Carbon::now()->getTimestamp() + 121), $legId);
        $this->assertJsonApiError(422, 'QR_EXPIRED');
        $this->scan($this->driver, $this->dynamicQr($device, $userId, Carbon::now()->getTimestamp() - 119), $legId);
        $this->assertResponseOk();

        // Firmado con otra clave que no es la del certificado.
        list($otherKey) = $this->deviceKey();
        $this->scan($this->driver, $this->dynamicQr([$device[0], $otherKey], $userId), $legId);
        $this->assertJsonApiError(422, 'QR_SIGNATURE_INVALID');

        // Payload cambiado después de firmar.
        $parts = explode('.', $this->dynamicQr($device, $userId));
        $parts[3] = QrCodes::base64UrlEncode(json_encode(['u' => $userId, 't' => Carbon::now()->getTimestamp(), 'n' => '0000000000000000']));
        $this->scan($this->driver, implode('.', $parts), $legId);
        $this->assertJsonApiError(422, 'QR_SIGNATURE_INVALID');

        $this->scan($this->driver, 'https://example.com/no-es-de-miruta', $legId);
        $this->assertJsonApiError(422, 'QR_INVALID');

        // El certificado caduca a los 30 días.
        Carbon::setTestNow(Carbon::now()->addDays(31));
        $this->scan($this->driver, $this->dynamicQr($device, $userId), null);
        $this->assertJsonApiError(422, 'QR_CERTIFICATE_EXPIRED');
    }

    public function testCertificadoAjeno()
    {
        $legId = $this->startLeg();
        $other = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $deviceOfOther = $this->device($other->user);

        // Con el certificado de otra persona no puede presentarse como el trabajador.
        $this->scan($this->driver, $this->dynamicQr($deviceOfOther, (int) $this->member->user_id), $legId);
        $this->assertJsonApiError(422, 'QR_CERTIFICATE_INVALID');

        // Certificado hecho por su cuenta (no lo firmó el servidor).
        list($private, $public) = $this->deviceKey();
        $json = json_encode(['u' => (int) $this->member->user_id, 'k' => $public, 'e' => Carbon::now()->addDays(30)->getTimestamp(), 'v' => 1], JSON_UNESCAPED_SLASHES);
        openssl_sign($json, $signature, $private, OPENSSL_ALGO_SHA256);
        $forged = QrCodes::base64UrlEncode($json).'.'.QrCodes::base64UrlEncode($signature);
        $this->scan($this->driver, $this->dynamicQr([$forged, $private], (int) $this->member->user_id), $legId);
        $this->assertJsonApiError(422, 'QR_CERTIFICATE_INVALID');
    }

    /*
    |--------------------------------------------------------------------------
    | QR impreso
    |--------------------------------------------------------------------------
    */

    public function testQrImpresoUsoDobleYAnulacion()
    {
        $legId = $this->startLeg();
        $noPhone = $this->joinItinerary($this->createWorker(['user' => ['has_phone' => false]]), $this->itinerary, 3);
        $chief = $this->createItineraryChief($this->itinerary);

        $this->jsonApiAs($this->member, 'GET', '/api/v1/workers/'.$noPhone->id.'/printed-qr');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($chief, 'GET', '/api/v1/workers/'.$this->member->id.'/printed-qr');
        $this->assertJsonApiError(409, 'PRINTED_QR_NOT_AVAILABLE');

        $this->jsonApiAs($chief, 'GET', '/api/v1/workers/'.$noPhone->id.'/printed-qr');
        $this->assertResponseOk();
        $attributes = $this->responseJson()['data']['attributes'];
        $printed = $attributes['qr'];
        $this->assertStringStartsWith('MRP1.', $printed);
        $this->assertSame(['u' => (int) $noPhone->user_id, 'v' => 1], json_decode(QrCodes::base64UrlDecode(explode('.', $printed)[1]), true));
        $this->assertSame($noPhone->user->sex, $attributes['sex']);

        $this->scan($this->driver, $printed, $legId);
        $this->assertResponseOk();
        $this->assertSame('printed', $this->responseJson()['data']['attributes']['kind']);

        $this->boardQr($this->driver, $legId, $printed);
        $this->assertResponseStatus(201);
        $this->seeJson(['qrKind' => 'printed']);

        // Una sola subida por trayecto: si el mismo QR impreso se usa dos veces, se avisa.
        $this->scan($this->driver, $printed, $legId);
        $this->assertTrue($this->responseJson()['data']['attributes']['alreadyBoarded']);
        $this->assertStringContainsString('copia', $this->responseJson()['data']['attributes']['warning']);
        $this->boardQr($this->driver, $legId, $printed);
        $this->assertJsonApiError(409, 'ALREADY_BOARDED');
        $this->assertStringContainsString('copia', $this->responseJson()['errors'][0]['detail']);

        // Anular y generar uno nuevo.
        $this->jsonApiAs($chief, 'POST', '/api/v1/workers/'.$noPhone->id.'/printed-qr/revoke', ['data' => ['type' => 'printed-qrs', 'id' => (string) $noPhone->user_id]]);
        $this->assertResponseOk();
        $renewed = $this->responseJson()['data']['attributes']['qr'];
        $this->assertSame(2, $this->responseJson()['data']['attributes']['version']);
        $this->scan($this->driver, $printed);
        $this->assertJsonApiError(422, 'QR_REVOKED');
        $this->scan($this->driver, $renewed);
        $this->assertResponseOk();

        // Al entrar por primera vez en la app con su teléfono, el impreso se anula.
        $this->jsonApi('POST', '/api/v1/tokens', ['data' => ['type' => 'tokens', 'attributes' => ['username' => $noPhone->user->username, 'password' => self::PASSWORD]]]);
        $this->assertResponseStatus(201);
        $user = User::find($noPhone->user_id);
        $this->assertTrue($user->has_phone);
        $this->assertSame(3, $user->printed_qr_version);
        $this->scan($this->driver, $renewed);
        $this->assertJsonApiError(422, 'QR_REVOKED');
    }

    /*
    |--------------------------------------------------------------------------
    | Hijos, gente de fuera y corrección
    |--------------------------------------------------------------------------
    */

    public function testCadaHijoSubeUnaSolaVezPorTrayecto()
    {
        $legId = $this->startLeg();
        $otherParent = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $child = $this->createChild($this->member);
        \App\Models\ChildParent::create(['child_id' => $child->id, 'user_id' => $otherParent->user_id]);
        $tooOld = $this->createChild($this->member, '2000-01-01');

        $this->boardQr($this->driver, $legId, $this->qrOf($this->member), ['childIds' => [$tooOld->id]]);
        $this->assertJsonApiError(422, 'CHILD_NOT_ELIGIBLE');

        $this->boardQr($this->driver, $legId, $this->qrOf($this->member), ['childIds' => [$child->id]]);
        $this->assertResponseStatus(201);
        $boardingId = $this->responseJson()['data']['id'];

        // El otro padre no lo puede volver a subir en el mismo trayecto.
        $this->scan($this->driver, $this->qrOf($otherParent), $legId);
        $this->assertTrue($this->responseJson()['data']['attributes']['children'][0]['alreadyBoarded']);
        $this->boardQr($this->driver, $legId, $this->qrOf($otherParent), ['childIds' => [$child->id]]);
        $this->assertJsonApiError(409, 'CHILD_ALREADY_BOARDED');
        $this->assertSame(1, TripBoardingChild::count());

        // Se corrige: el niño iba con el otro padre.
        $this->jsonApiAs($this->driver, 'PATCH', '/api/v1/trip-boardings/'.$boardingId, ['data' => ['type' => 'trip-boardings', 'id' => $boardingId, 'attributes' => ['childIds' => []]]]);
        $this->assertResponseOk();
        $this->seeJson(['childrenCount' => 0]);
        $this->boardQr($this->driver, $legId, $this->qrOf($otherParent), ['childIds' => [$child->id]]);
        $this->assertResponseStatus(201);
        $this->assertSame([(int) $child->id], TripBoardingChild::pluck('child_id')->map(function ($id) {
            return (int) $id;
        })->all());

        // En el otro trayecto vuelve a contar.
        TripLeg::find($legId)->forceFill(['ended_at' => Carbon::now()])->save();
        $returnId = $this->startLeg('return');
        $this->boardQr($this->driver, $returnId, $this->qrOf($this->member), ['childIds' => [$child->id]]);
        $this->assertResponseStatus(201);
    }

    public function testSubidaDeAlguienDeOtroItinerarioODeOtraEntidad()
    {
        $legId = $this->startLeg();
        $otherItinerary = $this->createItinerary('Ruta Oeste', 2);
        $visitor = $this->joinItinerary($this->createWorker(), $otherItinerary);
        $foreign = $this->createWorker([], $this->createEntity('OTRA'));
        $withoutEntity = $this->createUser();

        $this->scan($this->driver, $this->qrOf($visitor), $legId);
        $this->assertSame('itinerary', $this->responseJson()['data']['attributes']['outsider']);
        $this->assertTrue($this->responseJson()['data']['attributes']['canAllowOutsider']);

        $qr = $this->qrOf($visitor);
        $this->boardQr($this->driver, $legId, $qr);
        $this->assertJsonApiError(409, 'OUTSIDER_CONFIRMATION_REQUIRED');
        $this->assertSame('itinerary', $this->responseJson()['errors'][0]['meta']['outsider']);
        // La confirmación pendiente no gastó el código.
        $this->boardQr($this->driver, $legId, $qr, ['allowOutsider' => true]);
        $this->assertResponseStatus(201);
        $this->seeJson(['outsider' => 'itinerary']);

        $this->boardQr($this->driver, $legId, $this->qrOf($foreign), ['allowOutsider' => true]);
        $this->assertResponseStatus(201);
        $this->seeJson(['outsider' => 'entity']);

        $this->boardQr($this->driver, $legId, $this->qrOf($withoutEntity), ['allowOutsider' => true]);
        $this->assertJsonApiError(422, 'NOT_A_WORKER');

        // Quien escanea sin tracking.allow_outsiders no lo puede dejar subir.
        $scanner = $this->createWorker();
        $this->assignRole($scanner, $this->roleWith('Escáner', ['tracking.scan_boarding' => 'entity', 'trips.view' => 'entity'])->name);
        $this->boardQr($scanner, $legId, $this->qrOf($this->joinItinerary($this->createWorker(), $otherItinerary)), ['allowOutsider' => true]);
        $this->assertJsonApiError(403, 'OUTSIDER_NOT_ALLOWED');
        // A los del itinerario sí.
        $this->boardQr($scanner, $legId, $this->qrOf($this->member));
        $this->assertResponseStatus(201);

        $this->assertSame(2, TripBoarding::whereNotNull('outsider')->count());
    }

    public function testCorreccionDePasajeros()
    {
        $legId = $this->startLeg();
        $this->boardQr($this->driver, $legId, $this->qrOf($this->member));
        $boardingId = $this->responseJson()['data']['id'];
        TripLeg::find($legId)->forceFill(['ended_at' => Carbon::now()->addMinutes(30)])->save();
        Carbon::setTestNow(Carbon::now()->addHours(2));
        $late = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);

        // Sin tracking.fix_passengers no se corrige.
        $this->jsonApiAs($this->member, 'DELETE', '/api/v1/trip-boardings/'.$boardingId);
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $scanner = $this->createWorker();
        $this->assignRole($scanner, $this->roleWith('Escáner', ['tracking.scan_boarding' => 'entity', 'trips.view' => 'entity'])->name);
        $this->jsonApiAs($scanner, 'POST', '/api/v1/trip-boardings', ['data' => ['type' => 'trip-boardings', 'attributes' => ['method' => 'manual'], 'relationships' => [
            'tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]], 'worker' => ['data' => ['type' => 'workers', 'id' => (string) $late->id]],
        ]]]);
        $this->assertJsonApiError(409, 'LEG_NOT_ACTIVE');

        // El chofer de partida tiene tracking.fix_passengers: añade y quita después del trayecto.
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/trip-boardings', ['data' => ['type' => 'trip-boardings', 'attributes' => ['method' => 'manual'], 'relationships' => [
            'tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]], 'worker' => ['data' => ['type' => 'workers', 'id' => (string) $late->id]],
        ]]]);
        $this->assertResponseStatus(201);

        $this->jsonApiAs($this->driver, 'DELETE', '/api/v1/trip-boardings/'.$boardingId);
        $this->assertResponseStatus(204);
        $this->assertSame(1, TripBoarding::count());
    }

    /*
    |--------------------------------------------------------------------------
    | Sin conexión
    |--------------------------------------------------------------------------
    */

    public function testListaParaEscanearSinConexion()
    {
        $noPhone = $this->joinItinerary($this->createWorker(['user' => ['has_phone' => false]]), $this->itinerary, 3);
        $child = $this->createChild($this->member);
        $this->createChild($this->member, '2000-01-01');
        $this->createWorker([], $this->createEntity('OTRA'));

        $this->jsonApiAs($this->member, 'GET', '/api/v1/entities/'.$this->defaultEntity()->id.'/scan-roster');
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->jsonApiAs($this->driver, 'GET', '/api/v1/entities/'.$this->defaultEntity()->id.'/scan-roster');
        $this->assertResponseOk();
        $attributes = $this->responseJson()['data']['attributes'];
        $workers = array_column($attributes['workers'], null, 'userId');
        $this->assertCount(Worker::where('entity_id', $this->defaultEntity()->id)->count(), $workers);
        $this->assertNull($workers[(string) $this->member->user_id]['printedQrVersion']);
        $this->assertSame(1, $workers[(string) $noPhone->user_id]['printedQrVersion']);
        $this->assertSame((string) $this->itinerary->id, $workers[(string) $this->member->user_id]['itineraryId']);
        $this->assertSame([(string) $child->id], array_column($attributes['children'], 'childId'));
        $this->assertSame([(string) $this->member->user_id], $attributes['children'][0]['parentUserIds']);
        $this->assertNotEmpty($attributes['serverPublicKey']);
    }

    public function testSincronizacionDeEscaneosSinConexion()
    {
        $legId = $this->startLeg();
        $device = $this->device($this->member->user);
        $scannedAt = Carbon::now()->addMinutes(10);
        $qr = $this->dynamicQr($device, (int) $this->member->user_id, $scannedAt->getTimestamp());
        $other = $this->joinItinerary($this->createWorker(), $this->itinerary, 3);
        $late = $this->dynamicQr($this->device($other->user), (int) $other->user_id, $scannedAt->getTimestamp() - 600);
        $admin = $this->createAdmin();
        $assigned = $this->createWorker();
        $assignQr = $this->qrOf($assigned, $scannedAt->getTimestamp());

        // El trayecto terminó y se sincroniza dos horas después.
        TripLeg::find($legId)->forceFill(['ended_at' => Carbon::now()->addMinutes(30)])->save();
        Carbon::setTestNow(Carbon::now()->addHours(2));

        $items = [
            ['type' => 'offline-scans', 'lid' => 'a', 'attributes' => ['purpose' => 'boarding', 'qr' => $qr, 'scannedAt' => $scannedAt->toIso8601String()],
                'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]]],
            ['type' => 'offline-scans', 'lid' => 'b', 'attributes' => ['purpose' => 'boarding', 'qr' => $late, 'scannedAt' => $scannedAt->toIso8601String()],
                'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]]],
            ['type' => 'offline-scans', 'lid' => 'c', 'attributes' => ['purpose' => 'boarding', 'qr' => 'basura', 'scannedAt' => $scannedAt->toIso8601String()],
                'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]]],
        ];
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/offline-scans', ['data' => $items]);
        $this->assertResponseOk();
        $results = array_column($this->responseJson()['data'], 'attributes', 'id');
        $this->assertSame('accepted', $results['a']['status']);
        $this->assertSame('rejected', $results['b']['status']);
        $this->assertSame('QR_EXPIRED', $results['b']['code']);
        $this->assertSame('QR_INVALID', $results['c']['code']);
        $boarding = TripBoarding::first();
        $this->assertEquals($scannedAt->getTimestamp(), $boarding->boarded_at->getTimestamp());

        // Reintento (se perdió la respuesta): no se duplica.
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/offline-scans', ['data' => [$items[0]]]);
        $this->assertSame('repeated', $this->responseJson()['data'][0]['attributes']['status']);
        $this->assertSame(1, TripBoarding::count());

        // Otro teléfono que escaneó el mismo código: se descarta.
        $this->jsonApiAs($this->createItineraryChief($this->itinerary), 'POST', '/api/v1/trip-boardings', ['data' => ['type' => 'trip-boardings',
            'attributes' => ['method' => 'qr', 'qr' => $qr, 'scannedAt' => $scannedAt->toIso8601String()],
            'relationships' => ['tripLeg' => ['data' => ['type' => 'trip-legs', 'id' => $legId]]]]]);
        $this->assertResponseOk();
        $this->seeJson(['repeated' => true]);

        // Alta en un itinerario hecha sin conexión.
        $stop = $this->itinerary->stops->last();
        $this->jsonApiAs($admin, 'POST', '/api/v1/offline-scans', ['data' => [
            ['type' => 'offline-scans', 'attributes' => ['purpose' => 'itinerary_assignment', 'qr' => $assignQr, 'scannedAt' => $scannedAt->toIso8601String()],
                'relationships' => ['itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) $this->itinerary->id]], 'stop' => ['data' => ['type' => 'stops', 'id' => (string) $stop->id]]]],
        ]]);
        $this->assertSame('accepted', $this->responseJson()['data'][0]['attributes']['status']);
        $this->assertSame((int) $this->itinerary->id, (int) Worker::find($assigned->id)->itinerary_id);

        // Más de 7 días después ya no se puede sincronizar.
        Carbon::setTestNow(Carbon::now()->addDays(8));
        $this->jsonApiAs($this->driver, 'POST', '/api/v1/offline-scans', ['data' => [$items[0]]]);
        $this->assertSame('QR_SCAN_TOO_OLD', $this->responseJson()['data'][0]['attributes']['code']);

        // Los códigos usados caducados se borran.
        $this->artisan('qr:purge-nonces');
        $this->assertSame(0, QrNonce::withTrashed()->count());
    }

    /*
    |--------------------------------------------------------------------------
    | Alta directa en un itinerario
    |--------------------------------------------------------------------------
    */

    public function testAltaDirectaEnUnItinerarioConElQr()
    {
        $admin = $this->createAdmin();
        $oldItinerary = $this->createItinerary('Ruta Vieja', 2);
        $person = $this->createItineraryChief($oldItinerary);
        $stop = $this->itinerary->stops->last();
        $assign = function ($who, string $qr, $itineraryId = null, $stopId = null) use ($stop) {
            return $this->jsonApiAs($who, 'POST', '/api/v1/itinerary-assignments', ['data' => ['type' => 'itinerary-assignments',
                'attributes' => ['qr' => $qr],
                'relationships' => [
                    'itinerary' => ['data' => ['type' => 'itineraries', 'id' => (string) ($itineraryId ?: $this->itinerary->id)]],
                    'stop' => ['data' => ['type' => 'stops', 'id' => (string) ($stopId ?: $stop->id)]],
                ],
            ]]);
        };

        // Por defecto, solo el Administrador.
        $assign($this->createItineraryChief($this->itinerary), $this->qrOf($person));
        $this->assertJsonApiError(403, 'FORBIDDEN');

        $this->scan($admin, $this->qrOf($person), null, 'itinerary_assignment');
        $this->assertResponseOk();
        $this->assertSame((string) $oldItinerary->id, $this->responseJson()['data']['attributes']['memberships'][0]['itineraryId']);
        $this->assertTrue($this->responseJson()['data']['attributes']['memberships'][0]['assignableByQr']);

        $qr = $this->qrOf($person);
        $assign($admin, $qr, null, $oldItinerary->stops->first()->id);
        $this->assertJsonApiError(422, 'STOP_NOT_IN_ITINERARY');

        $assign($admin, $qr);
        $this->assertResponseStatus(201);
        $this->assertSame((string) $oldItinerary->id, $this->responseJson()['data']['attributes']['previousItineraryId']);
        $worker = Worker::find($person->id);
        $this->assertSame((int) $this->itinerary->id, (int) $worker->itinerary_id);
        $this->assertSame((int) $stop->id, (int) $worker->stop_id);
        // Cambiar de itinerario no quita jefaturas.
        $this->assertTrue(\App\Models\WorkerRole::where('worker_id', $person->id)->where('itinerary_id', $oldItinerary->id)->exists());
        $this->assertSame(1, \App\Models\Notice::where('user_id', $person->user_id)->where('type', 'itinerary_assigned')->count());

        // El mismo código: reintento del mismo alta (200) o ya usado para otra cosa (409).
        $assign($admin, $qr);
        $this->assertResponseOk();
        $this->seeJson(['repeated' => true]);
        $assign($admin, $qr, $oldItinerary->id, $oldItinerary->stops->first()->id);
        $this->assertJsonApiError(409, 'QR_ALREADY_USED');

        // Solo si pertenece a esa Entidad.
        $foreign = $this->createWorker([], $this->createEntity('OTRA'));
        $assign($admin, $this->qrOf($foreign));
        $this->assertJsonApiError(422, 'NOT_A_MEMBER');

        // Un rol con members.assign_by_qr de su itinerario.
        $scanner = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $this->assignRole($scanner, $this->roleWith('Alta QR', ['members.assign_by_qr' => 'itinerary'])->name);
        $newcomer = $this->createWorker();
        $assign($scanner, $this->qrOf($newcomer));
        $this->assertResponseStatus(201);
        $assign($scanner, $this->qrOf($newcomer), $oldItinerary->id, $oldItinerary->stops->first()->id);
        $this->assertJsonApiError(403, 'FORBIDDEN');
    }
}
