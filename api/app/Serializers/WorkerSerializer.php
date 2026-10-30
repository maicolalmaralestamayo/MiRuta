<?php

namespace App\Serializers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;

/**
 * Solo datos públicos. El carné nunca sale por aquí: se devolverá únicamente
 * en /me y al Administrador (docs/02-procesos.md §2.1, Privacidad).
 */
class WorkerSerializer extends Serializer
{
    public function type(): string
    {
        return 'workers';
    }

    public function attributes(Model $worker, Request $request): array
    {
        return [
            'firstName' => $worker->first_name,
            'lastName' => $worker->last_name,
            'sex' => $worker->sex,
            'photoUrl' => $worker->photo_path ? url('storage/'.$worker->photo_path) : null,
            'isAdmin' => $worker->is_admin,
            'active' => ! $worker->trashed(),
            'createdAt' => $this->date($worker->created_at),
        ];
    }

    public function toOneRelationships(): array
    {
        return [
            'rank' => ['ranks', 'rank_id', 'rank'],
        ];
    }
}
