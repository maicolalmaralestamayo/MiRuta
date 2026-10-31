<?php

namespace App\Console\Commands;

use App\Models\Notice;
use App\Models\User;
use App\Services\Passwords;
use App\Services\Settings;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Avisa password_expiry_warning_days días antes de que caduque la
 * contraseña (una vez por periodo).
 */
class WarnPasswordExpiry extends Command
{
    protected $signature = 'passwords:warn-expiry';

    protected $description = 'Avisa a quien tiene la contraseña a punto de caducar';

    public function handle(Passwords $passwords, Settings $settings)
    {
        $days = $settings->int('password_expiry_warning_days');
        $warned = 0;

        if ($days > 0) {
            $now = Carbon::now();

            foreach (User::whereNotNull('password_changed_at')->cursor() as $user) {
                $expiresAt = $passwords->expiresAt($user);

                if (! $expiresAt || $expiresAt->lte($now) || $expiresAt->gt($now->copy()->addDays($days))) {
                    continue;
                }

                $already = Notice::where('user_id', $user->id)->where('type', Notice::TYPE_PASSWORD_EXPIRING)
                    ->where('created_at', '>=', $user->password_changed_at)->exists();

                if (! $already) {
                    Notice::create(['user_id' => $user->id, 'type' => Notice::TYPE_PASSWORD_EXPIRING]);
                    $warned++;
                }
            }
        }

        $this->info("Avisados: {$warned}.");
    }
}
