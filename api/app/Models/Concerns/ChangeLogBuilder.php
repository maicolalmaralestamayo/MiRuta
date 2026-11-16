<?php

namespace App\Models\Concerns;

use App\Services\ChangeLog;
use Illuminate\Database\Eloquent\Builder;

/**
 * Constructor de consultas que anota en el registro de cambios lo que va a
 * cambiar o borrar (docs/11 §11.65).
 */
class ChangeLogBuilder extends Builder
{
    public function update(array $values)
    {
        $log = app(ChangeLog::class);
        $table = $this->model->getTable();

        if (! $log->tracks($table)) {
            return parent::update($values);
        }

        $models = (clone $this)->get();
        $result = parent::update($values);
        $log->modelsChanged($table, $models, ChangeLog::UPDATE, $values);

        return $result;
    }

    public function delete()
    {
        $log = app(ChangeLog::class);
        $table = $this->model->getTable();

        if (! $log->tracks($table)) {
            return parent::delete();
        }

        $models = (clone $this)->get();
        // Lo que la base de datos borrará o vaciará en cascada, antes de borrar.
        $log->cascade($table, $models->pluck($this->model->getKeyName())->all());
        $result = parent::delete();
        $log->modelsChanged($table, $models, ChangeLog::DELETE);

        return $result;
    }
}
