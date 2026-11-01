<?php

namespace App\Console\Commands;

use App\Models\Notice;
use App\Models\User;
use App\Services\Passwords;
use App\Services\Settings;
use Carbon\Carbon;
use Illuminate\Console\Command;

/**
 * Avisa cada día, durante los últimos password_expiry_notice_days días (ajuste
 * de cada usuario), de que la contraseña está a punto de caducar
 * (docs/09-repaso-pantallas.md §14).
 */
class WarnPasswordExpiry extends Command
{
    protected $signature = 'passwords:warn-expiry';

    protected $description = 'Avisa a quien tiene la contraseña a punto de caducar';

    public function handle(Passwords $passwords, Settings $settings)
    {
        $now = Carbon::now();
        $warned = 0;

        foreach (User::whereNotNull('password_changed_at')->cursor() as $user) {
            $expiresAt = $passwords->expiresAt($user);
            $days = (int) $settings->get('password_expiry_notice_days', $user);

            if ($days <= 0 || ! $expiresAt || $expiresAt->lte($now) || $expiresAt->gt($now->copy()->addDays($days))) {
                continue;
            }

            $today = Notice::where('user_id', $user->id)->where('type', Notice::TYPE_PASSWORD_EXPIRING)
                ->where('created_at', '>=', $now->copy()->startOfDay())->exists();

            if (! $today) {
                Notice::create(['user_id' => $user->id, 'type' => Notice::TYPE_PASSWORD_EXPIRING]);
                $warned++;
            }
        }

        $this->info("Avisados: {$warned}.");
    }
}
