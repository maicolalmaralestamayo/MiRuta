<?php

use App\Models\ConversationTopic;
use Laravel\Lumen\Testing\DatabaseMigrations;

/**
 * Convenciones JSON:API con un recurso público (motivos de conversación).
 */
class JsonApiTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed', ['--class' => \Database\Seeders\RoleSeeder::class]);
        $this->artisan('db:seed', ['--class' => \Database\Seeders\ConversationTopicSeeder::class]);
    }

    public function testColeccionOrdenada()
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics');

        $this->assertResponseOk();
        $this->assertSame('application/vnd.api+json', $this->response->headers->get('Content-Type'));

        $json = $this->responseJson();
        $this->assertCount(9, $json['data']);
        $this->assertSame('Dar ideas', $json['data'][0]['attributes']['name']);
        $this->assertSame('conversation-topics', $json['data'][0]['type']);
        $this->assertSame(9, $json['meta']['total']);
        $this->assertNull($json['links']['next']);
    }

    public function testPaginacion()
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics?page[size]=2&page[number]=2&sort=id');

        $json = $this->responseJson();
        $this->assertCount(2, $json['data']);
        $this->assertSame(['total' => 9, 'page' => 2, 'size' => 2], $json['meta']);
        $this->assertStringContainsString('page%5Bnumber%5D=3', $json['links']['next']);
        $this->assertStringContainsString('page%5Bnumber%5D=1', $json['links']['prev']);
        $this->assertStringContainsString('page%5Bnumber%5D=5', $json['links']['last']);
    }

    public function testOrdenDescendente()
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics?sort=-name&page[size]=1');

        $this->assertSame('Solicitar información', $this->responseJson()['data'][0]['attributes']['name']);
    }

    public function testFiltro()
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics?filter[name]=reportar');
        $this->assertSame(5, $this->responseJson()['meta']['total']);

        $this->jsonApi('GET', '/api/v1/conversation-topics?filter[recipient]=developer');
        $this->assertSame(3, $this->responseJson()['meta']['total']);
    }

    public function testNoIncluyeBorrados()
    {
        ConversationTopic::where('name', 'Dar ideas')->first()->delete();

        $this->jsonApi('GET', '/api/v1/conversation-topics');

        $this->assertSame(8, $this->responseJson()['meta']['total']);
    }

    /**
     * @dataProvider invalidParameters
     */
    public function testParametrosInvalidos(string $query, string $parameter)
    {
        $this->jsonApi('GET', '/api/v1/conversation-topics?'.$query);

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
        $this->jsonApi('GET', '/api/v1/conversation-topics', null, ['Accept' => 'application/vnd.api+json; charset=utf-8']);

        $this->assertJsonApiError(406, 'NOT_ACCEPTABLE');
    }

    public function testRutaInexistente()
    {
        $this->jsonApi('GET', '/api/v1/no-existe');

        $this->assertJsonApiError(404, 'NOT_FOUND');
    }

    public function testMetodoNoPermitido()
    {
        $this->jsonApi('DELETE', '/api/v1/conversation-topics');

        $this->assertJsonApiError(405, 'METHOD_NOT_ALLOWED');
    }
}
