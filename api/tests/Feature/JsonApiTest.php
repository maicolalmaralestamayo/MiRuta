<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Convenciones JSON:API de toda la API: paginación, orden, filtros e include.
 */
class JsonApiTest extends TestCase
{
    public function test_paginacion_y_enlaces(): void
    {
        $admin = $this->createAdmin();

        foreach (range(1, 7) as $i) {
            $this->createEntity('E'.$i);
        }

        $response = $this->jsonApiAs($admin, 'GET', '/api/v1/entities?page[size]=5&page[number]=2&sort=-abbreviation')->assertOk()
            ->assertJsonCount(2, 'data')->assertJsonPath('meta.total', 7)->assertJsonPath('meta.page', 2)->assertJsonPath('meta.size', 5)
            ->assertJsonPath('data.0.attributes.abbreviation', 'E2');
        $this->assertNull($response->json('links.next'));
        $this->assertNotNull($response->json('links.prev'));
    }

    public function test_parametros_no_validos_dan_400_con_el_parametro(): void
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'GET', '/api/v1/entities?sort=color')->assertStatus(400)->assertJsonPath('errors.0.source.parameter', 'sort');
        $this->jsonApiAs($admin, 'GET', '/api/v1/entities?filter[color]=x')->assertStatus(400)->assertJsonPath('errors.0.source.parameter', 'filter[color]');
        $this->jsonApiAs($admin, 'GET', '/api/v1/entities?page[size]=500')->assertStatus(400);
        $this->jsonApiAs($admin, 'GET', '/api/v1/itineraries?include=nada')->assertStatus(400)->assertJsonPath('errors.0.source.parameter', 'include');
    }

    public function test_errores_de_validacion_con_puntero_y_tipo_equivocado(): void
    {
        $admin = $this->createAdmin();

        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', self::resource('itineraries', ['name' => 'X']))
            ->assertStatus(409)->assertJsonPath('errors.0.code', 'TYPE_MISMATCH');
        $this->jsonApiAs($admin, 'POST', '/api/v1/entities', self::resource('entities', ['abbreviation' => 'X']))
            ->assertStatus(422)->assertJsonPath('errors.0.code', 'VALIDATION_ERROR')->assertJsonPath('errors.0.source.pointer', '/data/attributes/name');
        $this->jsonApiAs($admin, 'DELETE', '/api/v1/entities/999')->assertNotFound();
        $this->jsonApiAs($admin, 'PUT', '/api/v1/entities/1', self::resource('entities'))->assertStatus(405);
    }

    public function test_include_de_relaciones(): void
    {
        $admin = $this->createAdmin();
        $entity = $this->createEntity();
        $itinerary = $this->createItinerary($entity);

        $this->jsonApiAs($admin, 'GET', "/api/v1/itineraries/{$itinerary->id}?include=entity")->assertOk()
            ->assertJsonPath('data.relationships.entity.data.id', (string) $entity->id)
            ->assertJsonPath('included.0.type', 'entities')
            ->assertJsonPath('data.meta.stopCount', 3);
    }
}
