<?php

namespace Tests;

use App\JsonApi\MediaType;
use App\Models\Entity;
use App\Models\Itinerary;
use App\Models\ItineraryStop;
use App\Models\Stop;
use App\Models\User;
use App\Models\VehicleType;
use App\Models\Worker;
use App\Services\Access;
use App\Services\TokenService;
use App\Support\IdentityCard;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Testing\TestResponse;

abstract class TestCase extends BaseTestCase
{
    use RefreshDatabase;

    /** Sin Mockery: las órdenes de consola (migrate:fresh) escriben su salida tal cual. */
    public $mockConsoleOutput = false;

    /** Contraseña de las cuentas de prueba (cumple la política). */
    public const PASSWORD = 'Secreto.123';

    private static int $sequence = 0;

    /**
     * Petición con las cabeceras de JSON:API.
     */
    protected function jsonApi(string $method, string $uri, ?array $document = null, array $headers = []): TestResponse
    {
        $server = ['HTTP_ACCEPT' => MediaType::JSON_API];

        if ($document !== null) {
            $server['CONTENT_TYPE'] = MediaType::JSON_API;
        }

        foreach ($headers as $name => $value) {
            $key = strtoupper(str_replace('-', '_', $name));
            $server[$key === 'CONTENT_TYPE' ? $key : 'HTTP_'.$key] = $value;
        }

        return $this->call($method, $uri, [], [], [], $server, $document === null ? null : json_encode($document));
    }

    /**
     * Petición JSON:API con la sesión de esa persona (o de la persona de la pertenencia).
     */
    protected function jsonApiAs(User|Worker $who, string $method, string $uri, ?array $document = null, array $headers = []): TestResponse
    {
        return $this->jsonApi($method, $uri, $document, $headers + ['Authorization' => 'Bearer '.$this->tokenFor($who)]);
    }

    protected function tokenFor(User|Worker $who): string
    {
        $user = $who instanceof Worker ? User::find($who->user_id) : $who;

        return app(TokenService::class)->issue($user, 'pruebas')['accessToken'];
    }

    protected static function resource(string $type, array $attributes = [], array $relationships = [], ?string $id = null): array
    {
        $data = ['type' => $type];

        if ($id !== null) {
            $data['id'] = $id;
        }

        if ($attributes) {
            $data['attributes'] = $attributes;
        }

        foreach ($relationships as $name => $value) {
            $data['relationships'][$name] = ['data' => $value === null ? null : ['type' => $value[0], 'id' => (string) $value[1]]];
        }

        return ['data' => $data];
    }

    /**
     * Carné válido y distinto en cada llamada (nacimiento a partir de 1980).
     */
    protected function newIdentityCard(?string $sex = null, ?string $birthDate = null): string
    {
        self::$sequence++;
        $birthDate = $birthDate ?: Carbon::create(1980, 1, 1)->addDays(self::$sequence)->toDateString();

        return IdentityCard::make($birthDate, $sex ?: (self::$sequence % 2 ? 'F' : 'M'), self::$sequence);
    }

    protected function createUser(array $attributes = []): User
    {
        $card = $attributes['identity_card'] ?? $this->newIdentityCard();
        unset($attributes['identity_card']);
        self::$sequence++;
        $user = new User();
        $user->forceFill(array_merge([
            'username' => 'usuario'.self::$sequence,
            'password' => Hash::make(self::PASSWORD),
            'password_changed_at' => Carbon::now(),
            'first_name' => 'Nombre'.self::$sequence,
            'middle_name' => null,
            'first_surname' => 'Apellido'.self::$sequence,
            'second_surname' => 'Otro',
            'is_admin' => false,
        ], IdentityCard::columns($card), $attributes))->save();

        return $user->fresh();
    }

    protected function createAdmin(): User
    {
        return $this->createUser(['is_admin' => true]);
    }

    protected function createEntity(string $abbreviation = 'PRUEBA', array $attributes = []): Entity
    {
        return Entity::create(['abbreviation' => $abbreviation, 'name' => 'Entidad '.$abbreviation] + $attributes);
    }

    protected function createStop(string $landmark = 'Parada'): Stop
    {
        self::$sequence++;

        return Stop::create([
            'landmark' => $landmark.' '.self::$sequence,
            'street' => 'Calle '.self::$sequence,
            'latitude' => 23.1 + self::$sequence / 1000,
            'longitude' => -82.3 - self::$sequence / 1000,
        ]);
    }

    /**
     * Itinerario con $stops paradas nuevas (en orden).
     */
    protected function createItinerary(Entity $entity, int $stops = 3, string $name = 'Ruta'): Itinerary
    {
        self::$sequence++;
        $itinerary = Itinerary::create(['entity_id' => $entity->id, 'name' => $name.' '.self::$sequence]);

        for ($i = 1; $i <= $stops; $i++) {
            ItineraryStop::create(['itinerary_id' => $itinerary->id, 'stop_id' => $this->createStop('Parada '.$i)->id, 'position' => $i]);
        }

        return $itinerary;
    }

    /**
     * Persona (nueva o dada) en la Entidad, con itinerario y parada opcionales.
     */
    protected function createWorker(Entity $entity, ?Itinerary $itinerary = null, ?int $stopId = null, ?User $user = null, array $attributes = []): Worker
    {
        $user = $user ?: $this->createUser();
        $worker = Worker::create(array_merge([
            'user_id' => $user->id,
            'entity_id' => $entity->id,
            'itinerary_id' => $itinerary?->id,
            'stop_id' => $stopId,
            'active' => true,
        ], $attributes));
        app(Access::class)->flush();

        return $worker->fresh();
    }

    protected function createChief(Itinerary $itinerary, ?int $stopId = null): Worker
    {
        return $this->createWorker(Entity::find($itinerary->entity_id), $itinerary, $stopId, null, ['is_chief' => true]);
    }

    protected function vehicleType(): VehicleType
    {
        return VehicleType::firstOrCreate(['name' => 'Guagua'], ['seats' => 40, 'standing' => 20]);
    }
}
