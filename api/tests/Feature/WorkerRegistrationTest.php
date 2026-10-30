<?php

use App\Models\Rank;
use App\Models\Worker;
use App\Support\CardNumber;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Laravel\Lumen\Testing\DatabaseMigrations;

class WorkerRegistrationTest extends TestCase
{
    use DatabaseMigrations;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed', ['--class' => 'RankSeeder']);
    }

    private function registration(array $attributes = [], $rankId = null): array
    {
        return [
            'data' => [
                'type' => 'workers',
                'attributes' => array_merge([
                    'cardNumber' => '92071648863',
                    'firstName' => 'Maicol',
                    'lastName' => 'Almarales Tamayo',
                    'password' => 'secreto123',
                ], $attributes),
                'relationships' => [
                    'rank' => ['data' => ['type' => 'ranks', 'id' => (string) ($rankId ?: Rank::where('precedence', 17)->value('id'))]],
                ],
            ],
        ];
    }

    public function testRegistroDelPrimerTrabajadorLoHaceAdministrador()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());

        $this->assertResponseStatus(201);
        $this->assertSame('application/vnd.api+json', $this->response->headers->get('Content-Type'));

        $worker = Worker::first();
        $this->assertSame(url('api/v1/workers/'.$worker->id), $this->response->headers->get('Location'));

        $this->seeJson([
            'type' => 'workers',
            'id' => (string) $worker->id,
            'firstName' => 'Maicol',
            'lastName' => 'Almarales Tamayo',
            'sex' => 'M',
            'isAdmin' => true,
            'active' => true,
        ]);
        $this->assertSame(['type' => 'ranks', 'id' => (string) $worker->rank_id], $this->responseJson()['data']['relationships']['rank']['data']);
    }

    public function testLosSiguientesNoSonAdministradores()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(['cardNumber' => '85010100022']));

        $this->assertResponseStatus(201);
        $this->seeJson(['isAdmin' => false, 'sex' => 'M']);
        $this->assertSame(1, Worker::where('is_admin', true)->count());
    }

    public function testElCarneSeGuardaCifradoYNoSeDevuelve()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());

        $row = DB::table('workers')->first();
        $this->assertStringNotContainsString('92071648863', $row->card_number_encrypted);
        $this->assertSame('92071648863', \Illuminate\Support\Facades\Crypt::decryptString($row->card_number_encrypted));
        $this->assertSame(CardNumber::hashOf('92071648863'), $row->card_number_hash);
        $this->assertTrue(Hash::check('secreto123', $row->password));

        $content = $this->response->getContent();
        $this->assertStringNotContainsString('92071648863', $content);
        $this->assertStringNotContainsString('cardNumber', $content);
        $this->assertStringNotContainsString('password', $content);
    }

    public function testCarneRepetido()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(['firstName' => 'Otro']));

        $this->assertJsonApiError(409, 'CARD_NUMBER_TAKEN', '/data/attributes/cardNumber');
        $this->assertSame(1, Worker::count());
    }

    public function testCarneRepetidoAunqueElTrabajadorEsteInactivo()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());
        Worker::first()->delete();

        $this->jsonApi('POST', '/api/v1/workers', $this->registration());

        $this->assertJsonApiError(409, 'CARD_NUMBER_TAKEN');
    }

    public function testCarneInvalido()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(['cardNumber' => '92023048863']));

        $this->assertJsonApiError(422, 'CARD_NUMBER_INVALID', '/data/attributes/cardNumber');
        $this->assertSame(0, Worker::count());
    }

    public function testCamposObligatoriosConMensajesEnEspanol()
    {
        $document = $this->registration();
        unset($document['data']['attributes']['firstName'], $document['data']['attributes']['password']);

        $this->jsonApi('POST', '/api/v1/workers', $document);

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/firstName');
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/password');
        $this->seeJson(['detail' => 'El campo nombre es obligatorio.']);
    }

    public function testContrasenaCorta()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(['password' => 'corta']));

        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/attributes/password');
    }

    public function testJerarquiaInexistenteOBorrada()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration([], 9999));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/rank/data/id');

        $rank = Rank::first();
        $rank->delete();
        $this->jsonApi('POST', '/api/v1/workers', $this->registration([], $rank->id));
        $this->assertJsonApiError(422, 'VALIDATION_ERROR', '/data/relationships/rank/data/id');
    }

    public function testSexoFemeninoCalculadoDelCarne()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(['cardNumber' => '92071648873']));

        $this->seeJson(['sex' => 'F']);
    }

    public function testTipoDeRecursoIncorrecto()
    {
        $document = $this->registration();
        $document['data']['type'] = 'ranks';

        $this->jsonApi('POST', '/api/v1/workers', $document);

        $this->assertJsonApiError(409, 'TYPE_MISMATCH', '/data/type');
    }

    public function testDocumentoSinData()
    {
        $this->jsonApi('POST', '/api/v1/workers', ['meta' => []]);

        $this->assertJsonApiError(400, 'BAD_REQUEST', '/data');
    }

    public function testTipoDeContenidoIncorrecto()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration(), ['Content-Type' => 'application/json']);

        $this->assertJsonApiError(415, 'UNSUPPORTED_MEDIA_TYPE');
        $this->assertSame(0, Worker::count());
    }

    public function testGuardaLaJerarquiaElegida()
    {
        $this->jsonApi('POST', '/api/v1/workers', $this->registration());

        $worker = Worker::first();
        $this->assertTrue($worker->rank->is(Rank::where('precedence', 17)->first()));
    }
}
