<?php

use App\JsonApi\MediaType;
use App\Models\Rank;
use App\Models\Worker;
use App\Services\TokenService;
use App\Support\CardNumber;
use Illuminate\Support\Facades\Hash;
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

    /**
     * Petición JSON:API autenticada como el trabajador indicado.
     */
    protected function jsonApiAs(Worker $worker, string $method, string $uri, ?array $document = null, array $headers = [])
    {
        return $this->jsonApi($method, $uri, $document, $headers + ['Authorization' => 'Bearer '.$this->accessTokenFor($worker)]);
    }

    protected function accessTokenFor(Worker $worker): string
    {
        return app(TokenService::class)->issue($worker, 'pruebas')['accessToken'];
    }

    /** @var int */
    private static $cardSequence = 0;

    /**
     * Crea un trabajador con un carné válido y único. Contraseña: secreto123.
     */
    protected function createWorker(array $attributes = []): Worker
    {
        $cardNumber = isset($attributes['card_number']) ? $attributes['card_number'] : $this->uniqueCardNumber();
        unset($attributes['card_number']);
        $card = CardNumber::tryParse($cardNumber);

        if (! isset($attributes['rank_id'])) {
            $rank = Rank::where('precedence', 17)->first()
                ?: Rank::create(['name' => 'Trabajador civil', 'precedence' => 17]);
            $attributes['rank_id'] = $rank->id;
        }

        $worker = new Worker();
        $worker->forceFill(array_merge([
            'card_number_encrypted' => $card->encrypt(),
            'card_number_hash' => $card->hash(),
            'username' => 'usuario'.self::$cardSequence,
            'first_name' => 'Nombre'.self::$cardSequence,
            'last_name' => 'Apellido'.self::$cardSequence,
            'sex' => $card->sex(),
            'password' => Hash::make('secreto123'),
            'is_admin' => false,
        ], $attributes))->save();

        return $worker->fresh();
    }

    /**
     * Carné válido distinto en cada llamada: la fecha de nacimiento avanza un
     * día por llamada desde el 1 de enero de 1970 (siglo XX).
     * Sexo: penúltimo dígito par → M, impar → F; alterna si no se indica.
     */
    protected function uniqueCardNumber(?string $sex = null): string
    {
        self::$cardSequence++;
        $birth = \Carbon\CarbonImmutable::create(1970, 1, 1)->addDays(self::$cardSequence);
        $sexDigit = $sex === 'F' ? '1' : ($sex === 'M' ? '2' : (string) (self::$cardSequence % 2 ? 1 : 2));

        return $birth->format('ymd').'000'.$sexDigit.'0';
    }

    protected function createTransportChief(array $attributes = []): Worker
    {
        $worker = $this->createWorker($attributes);
        \App\Models\TransportChief::create(['worker_id' => $worker->id]);

        return $worker->refreshRoles();
    }

    protected function createDriver(array $attributes = []): Worker
    {
        $worker = $this->createWorker($attributes);
        \App\Models\Driver::create(['worker_id' => $worker->id]);

        return $worker->refreshRoles();
    }

    protected function createAdmin(): Worker
    {
        return $this->createWorker(['is_admin' => true]);
    }

    /**
     * Crea un itinerario con paradas en orden (latitudes 23.10, 23.11, …).
     */
    protected function createItinerary(string $name = 'Ruta Este', int $stops = 3): \App\Models\Itinerary
    {
        $itinerary = \App\Models\Itinerary::create(['name' => $name]);

        for ($i = 1; $i <= $stops; $i++) {
            $stop = \App\Models\Stop::create([
                'landmark' => "{$name} parada {$i}",
                'street' => 'Calle '.$i,
                'latitude' => 23.1 + ($i - 1) / 100,
                'longitude' => -82.3,
            ]);
            \App\Models\ItineraryStop::create(['itinerary_id' => $itinerary->id, 'stop_id' => $stop->id, 'position' => $i]);
        }

        return $itinerary->fresh();
    }

    /**
     * Pone al trabajador como miembro del itinerario, en la parada indicada (1 = la primera).
     */
    protected function joinItinerary(Worker $worker, \App\Models\Itinerary $itinerary, int $position = 1): Worker
    {
        $worker->itinerary_id = $itinerary->id;
        $worker->stop_id = $itinerary->itineraryStops()->where('position', $position)->value('stop_id');
        $worker->save();

        return $worker;
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
