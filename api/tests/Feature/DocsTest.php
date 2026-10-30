<?php

class DocsTest extends TestCase
{
    public function testSwaggerUi()
    {
        $this->get('/docs');

        $this->assertResponseOk();
        $this->assertStringContainsString('swagger-ui', $this->response->getContent());
        $this->assertStringContainsString(url('docs/openapi.yaml'), $this->response->getContent());
    }

    public function testEspecificacionOpenApi()
    {
        $this->get('/docs/openapi.yaml');

        $this->assertResponseOk();
        $this->assertStringStartsWith('openapi: 3.0.3', $this->response->getContent());
    }
}
