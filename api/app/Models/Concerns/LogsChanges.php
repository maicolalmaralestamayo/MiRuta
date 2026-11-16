<?php

namespace App\Models\Concerns;

use App\Services\ChangeLog;

/**
 * Las altas, cambios y bajas del modelo quedan en el registro de cambios
 * (docs/11 §11.65), también las hechas en masa (Model::where()->update()) y las
 * que la base de datos hace en cascada. Las altas se registran con el evento
 * «created»; los cambios y las bajas, en el constructor de consultas
 * (ChangeLogBuilder), que usan también save() y delete() del modelo.
 */
trait LogsChanges
{
    public static function bootLogsChanges(): void
    {
        static::created(fn ($model) => app(ChangeLog::class)->modelsChanged($model->getTable(), collect([$model]), ChangeLog::CREATE));
    }

    public function newEloquentBuilder($query)
    {
        return new ChangeLogBuilder($query);
    }
}
