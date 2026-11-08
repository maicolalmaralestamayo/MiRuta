<?php

namespace Tests\Feature;

use App\Models\AccessRecovery;
use App\Models\Notification;
use App\Models\RefreshToken;
use App\Models\User;
use Tests\TestCase;

/**
 * «Olvidé algo» (docs/11 §11.7), sin cuenta, desde una instalación de la app.
 */
class AccessRecoveryTest extends TestCase
{
    private function installation(): string
    {
        return $this->jsonApi('POST', '/api/v1/installations', self::resource('installations', ['deviceModel' => 'Moto G']))
            ->assertCreated()->json('data.meta.header');
    }

    public function test_el_administrador_aprueba_y_la_instalacion_ve_solo_lo_pedido(): void
    {
        $admin = $this->createAdmin();
        $card = $this->newIdentityCard();
        $user = $this->createUser(['identity_card' => $card, 'username' => 'pepe']);
        $this->tokenFor($user);
        $header = ['X-Installation' => $this->installation()];

        $this->jsonApi('POST', '/api/v1/guest/access-recoveries', self::resource('access-recoveries', [
            'forgotUsername' => true, 'forgotPassword' => true, 'identityCard' => $card, 'phone' => '+53 5 1234567',
        ]))->assertStatus(401)->assertJsonPath('errors.0.code', 'INSTALLATION_REQUIRED');

        $id = $this->jsonApi('POST', '/api/v1/guest/access-recoveries', self::resource('access-recoveries', [
            'forgotUsername' => true, 'forgotPassword' => true, 'identityCard' => $card, 'phone' => '+53 5 1234567',
        ]), $header)->assertCreated()->assertJsonPath('data.attributes.status', 'pending')->json('data.id');
        $this->assertSame(1, Notification::where('user_id', $admin->id)->where('kind', 'olvide_recibida')->count());

        $this->jsonApiAs($user, 'PATCH', "/api/v1/access-recoveries/{$id}", self::resource('access-recoveries', ['status' => 'approved']))->assertForbidden();
        $this->jsonApiAs($admin, 'GET', '/api/v1/access-recoveries')->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.attributes.phone', '+53 5 1234567')->assertJsonPath('data.0.attributes.matched', true);
        $password = $this->jsonApiAs($admin, 'PATCH', "/api/v1/access-recoveries/{$id}", self::resource('access-recoveries', ['status' => 'approved']))
            ->assertOk()->json('data.attributes.password');

        $this->assertTrue(User::find($user->id)->must_change_password);
        $this->assertSame(0, RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')->count());

        $this->jsonApi('GET', "/api/v1/guest/access-recoveries/{$id}", null, $header)->assertOk()
            ->assertJsonPath('data.attributes.username', 'pepe')->assertJsonPath('data.attributes.password', $password);
        // Leída una vez, ya no se vuelve a mostrar.
        $this->assertArrayNotHasKey('password', $this->jsonApi('GET', "/api/v1/guest/access-recoveries/{$id}", null, $header)->json('data.attributes'));
        $this->jsonApi('POST', '/api/v1/tokens', self::resource('tokens', ['username' => 'pepe', 'password' => $password]))->assertCreated();
    }

    public function test_limite_por_hora_y_rechazo(): void
    {
        $admin = $this->createAdmin();
        $header = ['X-Installation' => $this->installation()];
        $document = self::resource('access-recoveries', ['forgotUsername' => false, 'forgotPassword' => true, 'identityCard' => $this->newIdentityCard(), 'phone' => '55555555']);

        for ($i = 0; $i < 3; $i++) {
            $this->jsonApi('POST', '/api/v1/guest/access-recoveries', $document, $header)->assertCreated();
        }
        $this->jsonApi('POST', '/api/v1/guest/access-recoveries', $document, $header)->assertStatus(429);

        $id = AccessRecovery::where('status', 'pending')->value('id');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/access-recoveries/{$id}", self::resource('access-recoveries', ['status' => 'approved']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'RECOVERY_NOT_MATCHED');
        $this->jsonApiAs($admin, 'PATCH', "/api/v1/access-recoveries/{$id}", self::resource('access-recoveries', ['status' => 'rejected']))
            ->assertOk()->assertJsonPath('data.attributes.status', 'rejected');
    }
}
