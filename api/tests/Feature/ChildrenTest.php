<?php

namespace Tests\Feature;

use App\Models\Child;
use Carbon\Carbon;
use Tests\TestCase;

/**
 * Hijos (docs/11 §11.11): los padres los añaden, corrigen y quitan.
 */
class ChildrenTest extends TestCase
{
    public function test_los_padres_declaran_al_mismo_hijo_y_se_verifica_el_derecho(): void
    {
        $mother = $this->createUser();
        $father = $this->createUser();
        $stranger = $this->createUser();
        // Sin carné (docs/11 §11.67): el mismo niño es el de iguales nombres y fecha de nacimiento.
        $birth = Carbon::now()->subYears(6)->toDateString();
        $document = self::resource('children', ['firstName' => 'Pepito', 'firstSurname' => 'Pérez', 'secondSurname' => 'Gil', 'birthDate' => $birth]);

        $id = $this->jsonApiAs($mother, 'POST', '/api/v1/children', $document)->assertCreated()
            ->assertJsonPath('data.attributes.eligible', true)->assertJsonPath('meta.alreadyDeclared', false)->json('data.id');
        $this->jsonApiAs($father, 'POST', '/api/v1/children', self::resource('children', ['firstName' => 'pepito', 'firstSurname' => 'Pérez ',
            'secondSurname' => 'Gil', 'birthDate' => $birth]))->assertCreated()->assertJsonPath('meta.alreadyDeclared', true)
            ->assertJsonPath('data.attributes.sex', 'M');
        $this->jsonApiAs($mother, 'POST', '/api/v1/children', $document)->assertStatus(409);
        $this->assertSame(1, Child::count());

        $this->jsonApiAs($mother, 'GET', "/api/v1/children/{$id}")->assertJsonCount(2, 'data.meta.parents');
        $this->jsonApiAs($stranger, 'GET', "/api/v1/children/{$id}")->assertNotFound();

        $old = Carbon::now()->subYears(30)->toDateString();
        $this->jsonApiAs($mother, 'POST', '/api/v1/children', self::resource('children', ['firstName' => 'Ana', 'firstSurname' => 'A', 'secondSurname' => 'B', 'sex' => 'F', 'birthDate' => $old]))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'CHILD_NOT_ELIGIBLE');
        $this->jsonApiAs($mother, 'POST', '/api/v1/children', self::resource('children', ['firstName' => 'Ana', 'firstSurname' => 'A', 'secondSurname' => 'B']))
            ->assertStatus(422);
        $this->jsonApiAs($mother, 'PATCH', "/api/v1/children/{$id}", self::resource('children', ['sex' => 'F']))->assertOk()->assertJsonPath('data.attributes.sex', 'F');

        $this->jsonApiAs($mother, 'PATCH', "/api/v1/children/{$id}", self::resource('children', ['active' => false]))->assertOk()->assertJsonPath('data.attributes.active', false);
        $this->jsonApiAs($mother, 'DELETE', "/api/v1/children/{$id}")->assertNoContent();
        $this->assertSame(1, Child::count());
        $this->jsonApiAs($father, 'DELETE', "/api/v1/children/{$id}")->assertNoContent();
        $this->assertSame(0, Child::count());
    }
}
