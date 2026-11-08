<?php

namespace Tests\Feature;

use Tests\TestCase;

/**
 * Swagger UI y la especificación OpenAPI (solo con DOCS_ENABLED=true).
 */
class DocsTest extends TestCase
{
    public function test_swagger_y_especificacion(): void
    {
        $this->get('/docs')->assertOk()->assertSee('swagger-ui', false);
        $this->get('/docs/openapi.yaml')->assertOk()->assertSee('openapi: 3.0.3', false)->assertSee('/trips/{id}/reports', false);
    }
}
