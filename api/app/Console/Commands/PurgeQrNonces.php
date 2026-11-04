<?php

namespace App\Console\Commands;

use App\Services\QrCodes;
use Illuminate\Console\Command;

class PurgeQrNonces extends Command
{
    protected $signature = 'qr:purge-nonces';

    protected $description = 'Borra los códigos QR ya usados que caducaron (ya no se pueden volver a presentar)';

    public function handle(QrCodes $codes)
    {
        $this->info('Borrados: '.$codes->purgeExpiredNonces().'.');
    }
}
