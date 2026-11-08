<?php

namespace Tests\Feature;

use App\Models\RefreshToken;
use App\Models\User;
use Tests\TestCase;

class AuthTest extends TestCase
{
    public function test_el_primer_registro_es_el_administrador_y_el_segundo_no(): void
    {
        $this->jsonApi('GET', '/api/v1/registration-status')->assertOk()->assertJsonPath('data.attributes.adminExists', false);

        $document = fn (string $username) => self::resource('users', [
            'firstName' => 'Maicol', 'firstSurname' => 'Almarales', 'secondSurname' => 'Tamayo',
            'identityCard' => $this->newIdentityCard(), 'username' => $username, 'password' => 'Clave.Segura1',
        ]);

        $this->jsonApi('POST', '/api/v1/users', $document('maicol'))->assertCreated()
            ->assertHeader('Content-Type', 'application/vnd.api+json')
            ->assertJsonPath('data.attributes.isAdmin', true)
            ->assertJsonPath('data.attributes.username', 'maicol');

        $this->jsonApi('POST', '/api/v1/users', $document('otro'))->assertCreated()->assertJsonPath('data.attributes.isAdmin', false);
        $this->jsonApi('GET', '/api/v1/registration-status')->assertJsonPath('data.attributes.adminExists', true);
    }

    public function test_carne_repetido_da_el_texto_acordado(): void
    {
        $card = $this->newIdentityCard();
        $this->createUser(['identity_card' => $card]);

        $this->jsonApi('POST', '/api/v1/users', self::resource('users', [
            'firstName' => 'Ana', 'firstSurname' => 'Pérez', 'secondSurname' => 'Gil',
            'identityCard' => $card, 'username' => 'ana.perez', 'password' => 'Clave.Segura1',
        ]))->assertStatus(409)->assertJsonPath('errors.0.code', 'IDENTITY_CARD_TAKEN');
    }

    public function test_inicio_de_sesion_renovacion_y_cierre(): void
    {
        $user = $this->createUser(['username' => 'pepe']);

        $this->jsonApi('POST', '/api/v1/tokens', self::resource('tokens', ['username' => 'pepe', 'password' => 'mala']))
            ->assertStatus(401)->assertJsonPath('errors.0.code', 'INVALID_CREDENTIALS');

        $tokens = $this->jsonApi('POST', '/api/v1/tokens', self::resource('tokens', ['username' => 'PEPE', 'password' => self::PASSWORD]))
            ->assertCreated()->json('data.attributes');

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$tokens['accessToken']])
            ->assertOk()->assertJsonPath('data.id', (string) $user->id)->assertJsonPath('data.meta.role', 'trabajador');

        $renewed = $this->jsonApi('POST', '/api/v1/tokens/refresh', self::resource('tokens', ['refreshToken' => $tokens['refreshToken']]))
            ->assertCreated()->json('data.attributes');

        // Reutilizar un token de renovación ya usado cierra todas las sesiones.
        $this->jsonApi('POST', '/api/v1/tokens/refresh', self::resource('tokens', ['refreshToken' => $tokens['refreshToken']]))
            ->assertStatus(401)->assertJsonPath('errors.0.code', 'TOKEN_REVOKED');
        $this->assertSame(0, RefreshToken::where('user_id', $user->id)->whereNull('revoked_at')->count());

        $this->jsonApi('GET', '/api/v1/me', null, ['Authorization' => 'Bearer '.$renewed['accessToken']])
            ->assertStatus(401)->assertJsonPath('errors.0.code', 'TOKEN_REVOKED');
    }

    public function test_cerrar_sesion_anula_el_token(): void
    {
        $user = $this->createUser();
        $token = $this->tokenFor($user);
        $headers = ['Authorization' => 'Bearer '.$token];

        $this->jsonApi('DELETE', '/api/v1/tokens/current', null, $headers)->assertNoContent();
        $this->jsonApi('GET', '/api/v1/me', null, $headers)->assertStatus(401);
    }

    public function test_sin_token_y_negociacion_jsonapi(): void
    {
        $this->jsonApi('GET', '/api/v1/me')->assertStatus(401)->assertJsonPath('errors.0.code', 'UNAUTHENTICATED');
        $this->call('POST', '/api/v1/tokens', [], [], [], ['HTTP_ACCEPT' => 'application/vnd.api+json', 'CONTENT_TYPE' => 'application/json'], '{}')
            ->assertStatus(415)->assertJsonPath('errors.0.code', 'UNSUPPORTED_MEDIA_TYPE');
        $this->jsonApi('GET', '/api/v1/no-existe')->assertStatus(404)->assertJsonPath('errors.0.code', 'NOT_FOUND');
    }

    public function test_contrasena_puesta_por_otro_obliga_a_cambiarla(): void
    {
        $user = $this->createUser(['must_change_password' => true]);

        $this->jsonApiAs($user, 'GET', '/api/v1/entities')->assertStatus(403)->assertJsonPath('errors.0.code', 'PASSWORD_CHANGE_REQUIRED');
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['password' => 'Nueva.Clave9']))->assertOk()
            ->assertJsonPath('data.attributes.mustChangePassword', false);
        $this->jsonApiAs(User::find($user->id), 'GET', '/api/v1/entities')->assertOk();
    }

    public function test_cambiar_la_contrasena_exige_la_actual(): void
    {
        $user = $this->createUser();

        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', self::resource('users', ['password' => 'Nueva.Clave9']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'CURRENT_PASSWORD_INVALID');

        $document = self::resource('users', ['password' => 'Nueva.Clave9']) + ['meta' => ['currentPassword' => self::PASSWORD]];
        $this->jsonApiAs($user, 'PATCH', '/api/v1/me', $document)->assertOk();
    }
}
