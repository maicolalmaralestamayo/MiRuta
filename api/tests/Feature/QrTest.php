<?php

namespace Tests\Feature;

use App\Models\User;
use App\Models\Worker;
use App\Services\QrCodes;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * «Incluir por QR» (docs/11 §11.19 y §11.27) con el QR dinámico de la persona.
 */
class QrTest extends TestCase
{
    /**
     * Clave del teléfono y su certificado firmado por el servidor.
     *
     * @return array{0: string, 1: \OpenSSLAsymmetricKey}
     */
    private function device(User $user): array
    {
        $key = openssl_pkey_new(['private_key_type' => OPENSSL_KEYTYPE_EC, 'curve_name' => 'prime256v1']);
        $public = QrCodes::pemToBase64(openssl_pkey_get_details($key)['key']);
        $certificate = $this->jsonApiAs($user, 'POST', '/api/v1/me/qr-devices', self::resource('qr-devices', ['publicKey' => $public]))
            ->assertCreated()->json('data.attributes.certificate');

        return [$certificate, $key];
    }

    private function qr(array $device, int $userId, ?int $time = null, ?string $nonce = null): string
    {
        $payload = json_encode(['u' => $userId, 't' => $time ?? Carbon::now()->getTimestamp(), 'n' => $nonce ?: bin2hex(random_bytes(8))]);
        openssl_sign($payload, $signature, $device[1], OPENSSL_ALGO_SHA256);

        return 'MR1.'.$device[0].'.'.QrCodes::base64UrlEncode($payload).'.'.QrCodes::base64UrlEncode($signature);
    }

    private function include(User|Worker $scanner, string $qr, array $relationships, array $attributes = [])
    {
        return $this->jsonApiAs($scanner, 'POST', '/api/v1/qr-inclusions', self::resource('qr-inclusions', ['qr' => $qr] + $attributes, $relationships));
    }

    public function test_clave_publica_y_certificado(): void
    {
        $this->jsonApi('GET', '/api/v1/qr-public-key')->assertOk()->assertJsonPath('data.attributes.algorithm', 'ES256')
            ->assertJsonPath('data.attributes.refreshSeconds', 15);
        $this->jsonApiAs($this->createUser(), 'POST', '/api/v1/me/qr-devices', self::resource('qr-devices', ['publicKey' => 'no-es-una-clave']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'QR_DEVICE_KEY_INVALID');
    }

    public function test_el_administrador_incluye_en_una_entidad_y_dice_donde_esta_ya(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $person = $this->createUser();
        $device = $this->device($person);

        $this->jsonApiAs($admin, 'POST', '/api/v1/qr-scans', self::resource('qr-scans', ['qr' => $this->qr($device, $person->id)]))
            ->assertOk()->assertJsonPath('data.attributes.fullName', $person->fullName())->assertJsonCount(0, 'data.attributes.memberships');

        $this->include($admin, $this->qr($device, $person->id), ['entity' => ['entities', $entity->id]])
            ->assertCreated()->assertJsonPath('data.attributes.previous.inEntity', false)
            ->assertJsonPath('data.relationships.itinerary.data', null);
        $this->assertTrue(Worker::where('user_id', $person->id)->where('entity_id', $entity->id)->exists());

        $this->jsonApiAs($admin, 'POST', '/api/v1/qr-scans', self::resource('qr-scans', ['qr' => $this->qr($device, $person->id)]))
            ->assertJsonPath('data.attributes.memberships.0.entity.abbreviation', 'PRUEBA');
    }

    public function test_incluir_en_una_parada_pone_la_entidad_y_anade_el_itinerario_sin_quitar_el_anterior(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $person = $this->createUser();
        $this->createWorker($entity, $other, $other->stopIds()[0], $person, ['is_chief' => true]);
        $device = $this->device($person);
        $stop = $itinerary->stopIds()[2];

        $this->include($admin, $this->qr($device, $person->id), ['stop' => ['stops', $stop]])
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'VALIDATION_ERROR');

        $this->include($admin, $this->qr($device, $person->id), ['itinerary' => ['itineraries', $itinerary->id], 'stop' => ['stops', $stop]])
            ->assertCreated()->assertJsonPath('data.attributes.previous.inEntity', true)->assertJsonPath('data.attributes.previous.inItinerary', false)
            ->assertJsonPath('data.relationships.stop.data.id', (string) $stop);
        $this->assertSame($stop, $this->placement($person, $itinerary)->stop_id);
        $this->assertTrue($this->placement($person, $other)->is_chief, 'Conserva el otro itinerario y su jefatura.');
        $this->jsonApiAs($admin, 'POST', '/api/v1/qr-scans', self::resource('qr-scans', ['qr' => $this->qr($device, $person->id)]))
            ->assertJsonCount(2, 'data.attributes.memberships.0.itineraries');
    }

    public function test_el_jefe_solo_incluye_en_su_itinerario(): void
    {
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $other = $this->createItinerary($entity);
        $chief = $this->createChief($itinerary);
        $person = $this->createUser();
        $device = $this->device($person);

        $this->include($chief, $this->qr($device, $person->id), ['entity' => ['entities', $entity->id]])->assertForbidden();
        $this->include($chief, $this->qr($device, $person->id), ['itinerary' => ['itineraries', $other->id]])->assertForbidden();
        $this->include($chief, $this->qr($device, $person->id), ['itinerary' => ['itineraries', $itinerary->id]])->assertCreated();

        // Un trabajador no incluye a nadie.
        $this->jsonApiAs($person, 'POST', '/api/v1/qr-scans', self::resource('qr-scans', ['qr' => $this->qr($device, $person->id)]))->assertForbidden();
    }

    public function test_un_solo_uso_reintento_sin_conexion_y_qr_caducado_o_falso(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);
        $person = $this->createUser();
        $device = $this->device($person);
        $qr = $this->qr($device, $person->id);
        $target = ['itinerary' => ['itineraries', $itinerary->id]];

        $this->include($admin, $qr, $target)->assertCreated();
        // Reintento de la misma inclusión (sincronización sin conexión): 200 y repeated.
        $this->include($admin, $qr, $target)->assertOk()->assertJsonPath('meta.repeated', true);
        // El mismo código para otra cosa: ya usado.
        $this->include($admin, $qr, ['entity' => ['entities', $this->createEntity('OTRA')->id]])
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'QR_ALREADY_USED');

        // Escaneado sin conexión hace una hora: vale con su hora.
        $old = Carbon::now()->subHour();
        $this->include($admin, $this->qr($device, $person->id, $old->getTimestamp()), $target, ['scannedAt' => $old->toIso8601String()])->assertCreated();
        // Caducado (más de 2 minutos de diferencia).
        $this->include($admin, $this->qr($device, $person->id, Carbon::now()->subMinutes(5)->getTimestamp()), $target)
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'QR_EXPIRED');
        // Firma falsa: el código de otra persona con este certificado.
        $other = $this->createUser();
        $this->include($admin, $this->qr($device, $other->id), $target)->assertStatus(422)->assertJsonPath('errors.0.code', 'QR_CERTIFICATE_INVALID');
        $this->include($admin, 'MR1.basura', $target)->assertStatus(422)->assertJsonPath('errors.0.code', 'QR_INVALID');
    }
}
