<?php

use App\Models\Rank;
use Laravel\Lumen\Testing\DatabaseMigrations;

class JsonApiTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed', ['--class' => \Database\Seeders\RankSeeder::class]);
    }

    public function testColeccionOrdenadaPorPrioridadPorDefecto()
    {
        $this->jsonApi('GET', '/api/v1/ranks');

        $this->assertResponseOk();
        $this->assertSame('application/vnd.api+json', $this->response->headers->get('Content-Type'));

        $json = $this->responseJson();
        $this->assertCount(18, $json['data']);
        $this->assertSame('Coronel', $json['data'][0]['attributes']['name']);
        $this->assertSame('ranks', $json['data'][0]['type']);
        $this->assertSame(18, $json['meta']['total']);
        $this->assertNull($json['links']['next']);
    }

    public function testPaginacion()
    {
        $this->jsonApi('GET', '/api/v1/ranks?page[size]=5&page[number]=2');

        $json = $this->responseJson();
        $this->assertCount(5, $json['data']);
        $this->assertSame('Primer teniente', $json['data'][0]['attributes']['name']);
        $this->assertSame(['total' => 18, 'page' => 2, 'size' => 5], $json['meta']);
        $this->assertStringContainsString('page%5Bnumber%5D=3', $json['links']['next']);
        $this->assertStringContainsString('page%5Bnumber%5D=1', $json['links']['prev']);
        $this->assertStringContainsString('page%5Bnumber%5D=4', $json['links']['last']);
    }

    public function testOrdenDescendente()
    {
        $this->jsonApi('GET', '/api/v1/ranks?sort=-precedence&page[size]=1');

        $this->assertSame('Otra categoría', $this->responseJson()['data'][0]['attributes']['name']);
    }

    public function testFiltro()
    {
        $this->jsonApi('GET', '/api/v1/ranks?filter[name]=sargento');

        $this->assertSame(3, $this->responseJson()['meta']['total']);
    }

    public function testNoIncluyeBorrados()
    {
        Rank::where('precedence', 1)->first()->delete();

        $this->jsonApi('GET', '/api/v1/ranks');

        $this->assertSame(17, $this->responseJson()['meta']['total']);
    }

    /**
     * @dataProvider invalidParameters
     */
    public function testParametrosInvalidos(string $query, string $parameter)
    {
        $this->jsonApi('GET', '/api/v1/ranks?'.$query);

        $this->assertJsonApiError(400, 'BAD_REQUEST');
        $this->assertSame($parameter, $this->responseJson()['errors'][0]['source']['parameter']);
    }

    public function invalidParameters(): array
    {
        return [
            'orden desconocido' => ['sort=color', 'sort'],
            'filtro desconocido' => ['filter[color]=rojo', 'filter[color]'],
            'página demasiado grande' => ['page[size]=101', 'page[size]'],
            'página no numérica' => ['page[number]=dos', 'page[number]'],
            'página cero' => ['page[number]=0', 'page[number]'],
            'include no permitido' => ['include=workers', 'include'],
        ];
    }

    public function testAcceptConParametrosNoPermitidos()
    {
        $this->jsonApi('GET', '/api/v1/ranks', null, ['Accept' => 'application/vnd.api+json; charset=utf-8']);

        $this->assertJsonApiError(406, 'NOT_ACCEPTABLE');
    }

    public function testRutaInexistente()
    {
        $this->jsonApi('GET', '/api/v1/no-existe');

        $this->assertJsonApiError(404, 'NOT_FOUND');
    }

    public function testMetodoNoPermitido()
    {
        $this->jsonApi('DELETE', '/api/v1/ranks');

        $this->assertJsonApiError(405, 'METHOD_NOT_ALLOWED');
    }
}
