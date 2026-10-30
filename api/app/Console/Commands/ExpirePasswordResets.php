<?php

namespace App\Console\Commands;

use App\Services\PasswordResets;
use Illuminate\Console\Command;

class ExpirePasswordResets extends Command
{
    protected $signature = 'password-resets:expire';

    protected $description = 'Cierra las solicitudes de restablecimiento caducadas y borra su teléfono y código';

    public function handle(PasswordResets $resets)
    {
        $this->info('Solicitudes caducadas: '.$resets->expireOld());
    }
}
