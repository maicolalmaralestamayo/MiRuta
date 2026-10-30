<?php

use App\JsonApi\MediaType;
use Laravel\Lumen\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    /**
     * Creates the application.
     *
     * @return \Laravel\Lumen\Application
     */
    public function createApplication()
    {
        return require __DIR__.'/../bootstrap/app.php';
    }

    /**
     * Petición con las cabeceras de JSON:API.
     */
    protected function jsonApi(string $method, string $uri, ?array $document = null, array $headers = [])
    {
        $server = [
            'HTTP_ACCEPT' => MediaType::JSON_API,
        ];

        if ($document !== null) {
            $server['CONTENT_TYPE'] = MediaType::JSON_API;
        }

        foreach ($headers as $name => $value) {
            $key = strtoupper(str_replace('-', '_', $name));
            $server[$key === 'CONTENT_TYPE' ? $key : 'HTTP_'.$key] = $value;
        }

        $this->call($method, $uri, [], [], [], $server, $document === null ? null : json_encode($document));

        return $this;
    }

    protected function responseJson(): array
    {
        return json_decode($this->response->getContent(), true);
    }

    /**
     * Comprueba que la respuesta contiene un error JSON:API con ese código.
     */
    protected function assertJsonApiError(int $status, string $code, ?string $pointer = null): void
    {
        $this->assertResponseStatus($status);
        $this->assertSame(MediaType::JSON_API, $this->response->headers->get('Content-Type'));

        $errors = $this->responseJson()['errors'];
        $matching = array_filter($errors, function ($error) use ($code, $pointer) {
            return $error['code'] === $code
                && ($pointer === null || (isset($error['source']['pointer']) && $error['source']['pointer'] === $pointer));
        });

        $this->assertNotEmpty($matching, "No se encontró el error {$code}".($pointer ? " en {$pointer}" : '').': '.json_encode($errors));
    }
}
