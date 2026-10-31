<?php

use App\Models\AbsenceApplication;
use App\Models\AbsenceType;
use App\Models\Application;
use App\Models\Notice;
use App\Models\Setting;
use App\Models\SettingDefinition;
use App\Models\Trip;
use App\Models\TripBoarding;
use App\Models\TripLeg;
use App\Models\Vehicle;
use App\Models\VehicleType;
use Carbon\Carbon;
use Laravel\Lumen\Testing\DatabaseMigrations;

class InactivityTest extends TestCase
{
    use DatabaseMigrations;

    private $itinerary;
    private $vehicle;
    private $driver;
    private $chief;

    protected function setUp(): void
    {
        parent::setUp();
        $this->artisan('db:seed');
        Carbon::setTestNow(Carbon::create(2026, 10, 1, 8));
        $this->itinerary = $this->createItinerary();
        $this->vehicle = $this->createVehicle(null, 10, 0);
        $this->driver = $this->createDriver();
        $this->chief = $this->createTransportChief();

        // 5 días sin viajar para la baja; aviso 2 días antes (ajustes de la Entidad)
        foreach (['inactivity_days' => '5', 'inactivity_warning_days' => '2'] as $key => $value) {
            \App\Models\EntitySetting::create(['entity_id' => $this->defaultEntity()->id, 'setting_definition_id' => SettingDefinition::where('key', $key)->value('id'), 'value' => $value]);
        }
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function completedTrip(int $day): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->itinerary->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $this->driver->driverId(),
            'departs_at' => Carbon::create(2026, 10, $day, 17), 'returns_at' => Carbon::create(2026, 10, $day + 1, 6),
            'status' => Trip::STATUS_COMPLETED, 'created_by' => $this->chief->user_id,
        ]);
    }

    private function boarded($worker, Trip $trip): void
    {
        $leg = TripLeg::create(['trip_id' => $trip->id, 'direction' => 'return', 'started_at' => $trip->returns_at, 'started_by' => $this->driver->user_id]);
        TripBoarding::create(['trip_leg_id' => $leg->id, 'worker_id' => $worker->id, 'method' => 'self', 'children_count' => 0, 'boarded_at' => $trip->returns_at]);
    }

    public function testAvisoYBajaPorInactividad()
    {
        $absent = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $regular = $this->joinItinerary($this->createWorker(), $this->itinerary);

        foreach (range(2, 4) as $day) {
            $this->boarded($regular, $this->completedTrip($day));
        }

        // Día 4: 3 días sin viajar = 5 - 2 → aviso
        Carbon::setTestNow(Carbon::create(2026, 10, 4, 23));
        $this->artisan('workers:inactivity');
        $this->assertTrue(Notice::where('user_id', $absent->user_id)->where('type', 'inactivity_warning')->exists());
        $this->assertFalse(Notice::where('user_id', $regular->user_id)->exists());

        // Repetir no avisa dos veces
        $this->artisan('workers:inactivity');
        $this->assertSame(1, Notice::where('user_id', $absent->user_id)->where('type', 'inactivity_warning')->count());

        foreach ([5, 6] as $day) {
            $this->boarded($regular, $this->completedTrip($day));
        }

        Carbon::setTestNow(Carbon::create(2026, 10, 6, 23));
        $this->artisan('workers:inactivity');

        $this->assertNull($absent->fresh()->itinerary_id);
        $this->assertSame($this->itinerary->id, (int) $regular->fresh()->itinerary_id);
        $removal = Application::where('worker_id', $absent->id)->where('type', 'itinerary_removal')->first();
        $this->assertSame('approved', $removal->status);
        $this->assertSame($this->itinerary->id, (int) $removal->itineraryApplication->itinerary_id);
        $this->assertTrue(Notice::where('user_id', $absent->user_id)->where('type', 'inactivity_removal')->exists());
    }

    public function testDiasSinViajesYAusenciasNoCuentan()
    {
        $worker = $this->joinItinerary($this->createWorker(), $this->itinerary);
        $application = Application::create(['worker_id' => $worker->id, 'type' => 'absence', 'status' => 'approved']);
        AbsenceApplication::create(['application_id' => $application->id, 'absence_type_id' => AbsenceType::first()->id, 'starts_on' => '2026-10-02', 'ends_on' => '2026-10-05']);

        // 6 viajes, 4 durante la ausencia → solo cuentan 2
        foreach (range(2, 7) as $day) {
            $this->completedTrip($day);
        }

        Carbon::setTestNow(Carbon::create(2026, 10, 20, 23));
        $this->artisan('workers:inactivity');

        $this->assertSame($this->itinerary->id, (int) $worker->fresh()->itinerary_id);
        $this->assertFalse(Notice::where('user_id', $worker->user_id)->exists());
    }

    private function completedTripDrivenBy($driverWorker, int $day): Trip
    {
        return Trip::create([
            'itinerary_id' => $this->createItinerary('Otra '.$day)->id, 'vehicle_id' => $this->vehicle->id, 'driver_id' => $driverWorker->driverId(),
            'departs_at' => Carbon::create(2026, 10, $day, 7), 'returns_at' => Carbon::create(2026, 10, $day, 9),
            'status' => Trip::STATUS_COMPLETED, 'created_by' => $this->chief->user_id,
        ]);
    }

    public function testConducirUnViajeRealizadoCuentaComoActividad()
    {
        // Un chofer miembro del itinerario que no sube como pasajero pero conduce.
        $driver = $this->joinItinerary($this->createDriver(), $this->itinerary);

        foreach (range(2, 7) as $day) {
            $this->completedTrip($day);
            $this->completedTripDrivenBy($driver, $day);
        }

        Carbon::setTestNow(Carbon::create(2026, 10, 7, 23));
        $this->artisan('workers:inactivity');

        $this->assertSame($this->itinerary->id, (int) $driver->fresh()->itinerary_id);
        $this->assertFalse(Notice::where('user_id', $driver->user_id)->exists());
    }

    public function testLosPlazosSonDeCadaEntidad()
    {
        $other = $this->createEntity('OTRA');
        $foreignItinerary = $this->createItinerary('Ajena', 2, $other);
        $foreign = $this->joinItinerary($this->createWorker([], $other), $foreignItinerary);
        $foreignDriver = $this->createDriver([], $other);
        $foreignVehicle = $this->createVehicle(null, 10, 0, $other);

        foreach (range(2, 7) as $day) {
            Trip::create([
                'itinerary_id' => $foreignItinerary->id, 'vehicle_id' => $foreignVehicle->id, 'driver_id' => $foreignDriver->driverId(),
                'departs_at' => Carbon::create(2026, 10, $day, 17), 'returns_at' => Carbon::create(2026, 10, $day + 1, 6),
                'status' => Trip::STATUS_COMPLETED, 'created_by' => $this->chief->user_id,
            ]);
        }

        Carbon::setTestNow(Carbon::create(2026, 10, 8, 23));
        $this->artisan('workers:inactivity');

        // La otra Entidad usa los 30 días de la app: sigue en su itinerario.
        $this->assertSame($foreignItinerary->id, (int) $foreign->fresh()->itinerary_id);
    }
}
