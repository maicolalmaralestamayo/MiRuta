<?php

use App\JsonApi\MediaType;
use App\Models\Entity;
use App\Models\Role;
use App\Models\User;
use App\Models\Worker;
use App\Models\WorkerRole;
use App\Support\IdentityCard;
use App\Services\TokenService;
use Carbon\Carbon;
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
     * Petición JSON:API autenticada como la cuenta (o el trabajador) indicada.
     */
    protected function jsonApiAs($who, string $method, string $uri, ?array $document = null, array $headers = [])
    {
        return $this->jsonApi($method, $uri, $document, $headers + ['Authorization' => 'Bearer '.$this->accessTokenFor($who)]);
    }

    /**
     * @param User|Worker $who
     */
    protected function accessTokenFor($who): string
    {
        return app(TokenService::class)->issue($this->userOf($who), 'pruebas')['accessToken'];
    }

    /**
     * @param User|Worker $who
     */
    protected function userOf($who): User
    {
        return $who instanceof Worker ? User::withTrashed()->find($who->user_id) : $who;
    }

    /** Contraseña de las cuentas de prueba (cumple la política). */
    const PASSWORD = 'Secreto.123';

    /** @var int */
    private static $sequence = 0;

    /** @var Entity|null */
    private $defaultEntity;

    protected function defaultEntity(): Entity
    {
        if (! $this->defaultEntity || ! Entity::whereKey($this->defaultEntity->id)->exists()) {
            $this->defaultEntity = Entity::where('abbreviation', 'PRUEBA')->first()
                ?: Entity::create(['abbreviation' => 'PRUEBA', 'name' => 'Entidad de pruebas']);
        }

        return $this->defaultEntity;
    }

    protected function createEntity(string $abbreviation, ?string $name = null): Entity
    {
        return Entity::create(['abbreviation' => $abbreviation, 'name' => $name ?: 'Entidad '.$abbreviation]);
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

    /**
     * Persona con cuenta. Contraseña: self::PASSWORD. Se puede indicar
     * 'identity_card' (carné en claro).
     */
    protected function createUser(array $attributes = []): User
    {
        $card = isset($attributes['identity_card']) ? $attributes['identity_card'] : $this->newIdentityCard();
        unset($attributes['identity_card']);
        self::$sequence++;
        $user = new User();
        $user->forceFill(array_merge([
            'username' => 'usuario'.self::$sequence,
            'password' => Hash::make(self::PASSWORD),
            'password_changed_at' => Carbon::now(),
            'first_name' => 'Nombre'.self::$sequence,
            'middle_name' => 'Segundo',
            'first_surname' => 'Apellido'.self::$sequence,
            'second_surname' => 'Otro',
            'is_admin' => false,
            'has_phone' => true,
        ], IdentityCard::columns($card), $attributes))->save();

        return $user->fresh();
    }

    /**
     * Roles de partida (los crea el seeder si no existen).
     */
    protected function role(string $name): Role
    {
        if (! Role::exists()) {
            (new \Database\Seeders\RoleSeeder())->run();
        }

        return Role::where('name', $name)->firstOrFail();
    }

    protected function assignRole(Worker $worker, string $roleName, ?int $itineraryId = null): WorkerRole
    {
        $workerRole = WorkerRole::create(['worker_id' => $worker->id, 'role_id' => $this->role($roleName)->id, 'itinerary_id' => $itineraryId]);
        app(\App\Services\Permissions::class)->flush();

        return $workerRole;
    }

    /**
     * Pertenencia (con su persona) en la Entidad de pruebas o la indicada, con
     * el rol Trabajador. Los atributos de la persona van en $attributes['user'];
     * con $attributes['user_id'], se usa esa persona.
     */
    protected function createWorker(array $attributes = [], ?Entity $entity = null): Worker
    {
        $userAttributes = isset($attributes['user']) ? $attributes['user'] : [];
        unset($attributes['user']);
        $userId = isset($attributes['user_id']) ? $attributes['user_id'] : $this->createUser($userAttributes)->id;
        $entity = $entity ?: $this->defaultEntity();

        $worker = new Worker();
        $worker->forceFill(array_merge([
            'user_id' => $userId,
            'entity_id' => $entity->id,
        ], $attributes))->save();
        $this->assignRole($worker, 'Trabajador');

        return $worker->fresh();
    }

    protected function createTransportChief(array $attributes = [], ?Entity $entity = null): Worker
    {
        $worker = $this->createWorker($attributes, $entity);
        $this->assignRole($worker, 'Jefe de Transporte');

        return $worker->fresh();
    }

    protected function createDriver(array $attributes = [], ?Entity $entity = null): Worker
    {
        $worker = $this->createWorker($attributes, $entity);
        $this->assignRole($worker, 'Chofer');

        return $worker->fresh();
    }

    protected function createItineraryChief(\App\Models\Itinerary $itinerary, array $attributes = []): Worker
    {
        $worker = $this->joinItinerary($this->createWorker($attributes, Entity::find($itinerary->entity_id)), $itinerary);
        $this->assignRole($worker, 'Jefe de itinerario', $itinerary->id);

        return $worker->fresh();
    }

    /**
     * Hijo declarado por la persona (o la persona de la pertenencia).
     */
    protected function createChild($parent, string $birthDate = '2018-05-05', array $attributes = []): \App\Models\Child
    {
        $child = new \App\Models\Child();
        $child->forceFill(array_merge([
            'first_name' => 'Niño'.(self::$sequence + 1), 'first_surname' => 'Apellido', 'second_surname' => 'Otro', 'active' => true,
        ], IdentityCard::columns($this->newIdentityCard(null, $birthDate)), $attributes))->save();
        \App\Models\ChildParent::create(['child_id' => $child->id, 'user_id' => $this->userOf($parent)->id]);

        return $child->fresh();
    }

    protected function createAdmin(): User
    {
        return $this->createUser(['is_admin' => true]);
    }

    protected function createStop(string $landmark = 'Parada', ?Entity $entity = null, float $latitude = 23.1): \App\Models\Stop
    {
        return \App\Models\Stop::create([
            'entity_id' => ($entity ?: $this->defaultEntity())->id,
            'landmark' => $landmark,
            'street' => 'Calle',
            'latitude' => $latitude,
            'longitude' => -82.3,
        ]);
    }

    /**
     * Crea un itinerario con paradas en orden (latitudes 23.10, 23.11, …).
     */
    protected function createItinerary(string $name = 'Ruta Este', int $stops = 3, ?Entity $entity = null): \App\Models\Itinerary
    {
        $entity = $entity ?: $this->defaultEntity();
        $itinerary = \App\Models\Itinerary::create(['name' => $name, 'entity_id' => $entity->id]);

        for ($i = 1; $i <= $stops; $i++) {
            $stop = $this->createStop("{$name} parada {$i}", $entity, 23.1 + ($i - 1) / 100);
            \App\Models\ItineraryStop::create(['itinerary_id' => $itinerary->id, 'stop_id' => $stop->id, 'position' => $i]);
        }

        return $itinerary->fresh();
    }

    protected function createVehicle(?Worker $driver = null, int $seats = 10, int $standing = 5, ?Entity $entity = null): \App\Models\Vehicle
    {
        $type = \App\Models\VehicleType::first() ?: \App\Models\VehicleType::create(['name' => 'Ómnibus']);
        self::$sequence++;

        return \App\Models\Vehicle::create([
            'entity_id' => ($entity ?: $this->defaultEntity())->id,
            'vehicle_type_id' => $type->id,
            'plate' => 'P'.self::$sequence,
            'seats' => $seats,
            'standing_capacity' => $standing,
            'driver_id' => $driver ? $driver->id : null,
        ]);
    }

    /**
     * Pone al trabajador como miembro del itinerario, en la parada indicada (1 = la primera).
     */
    protected function joinItinerary(Worker $worker, \App\Models\Itinerary $itinerary, int $position = 1): Worker
    {
        $worker->itinerary_id = $itinerary->id;
        $worker->stop_id = $itinerary->itineraryStops()->where('position', $position)->value('stop_id');
        $worker->save();
        app(\App\Services\Permissions::class)->flush();

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
