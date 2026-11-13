<?php

namespace App\Console\Commands;

use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Hash;

/**
 * Creates the first admin account from ADMIN_EMAIL / ADMIN_PASSWORD.
 *
 * There is no web install wizard: on container deployments the admin is
 * provisioned from environment variables on boot. It never touches an
 * existing admin, so it is safe to run on every start.
 */
class EnsureAdminUser extends Command
{
    protected $signature = 'app:ensure-admin';

    protected $description = 'Create the admin user from ADMIN_EMAIL / ADMIN_PASSWORD if no admin exists yet';

    public function handle(): int
    {
        // getenv() first: env() returns null once the config is cached.
        $email = getenv('ADMIN_EMAIL') ?: env('ADMIN_EMAIL');
        $password = getenv('ADMIN_PASSWORD') ?: env('ADMIN_PASSWORD');
        $name = getenv('ADMIN_NAME') ?: env('ADMIN_NAME', 'Admin');

        if (empty($email) || empty($password)) {
            $this->info('ADMIN_EMAIL / ADMIN_PASSWORD not set, skipping admin creation.');

            return Command::SUCCESS;
        }

        // ADAPT: how the project tells that an admin already exists.
        // Role package:  User::role('admin')->exists()
        // Boolean column: User::where('is_admin', true)->exists()
        if (User::role('admin')->exists()) {
            $this->info('Admin user already exists, skipping.');

            return Command::SUCCESS;
        }

        $user = User::where('email', $email)->first();

        if (! $user) {
            $user = new User();
            $user->forceFill([
                'name' => $name,
                'email' => $email,
                'password' => Hash::make($password),
                'email_verified_at' => now(),
            ])->save();
        }

        // ADAPT: how the project makes a user an admin.
        // Role package:  $user->assignRole('admin');
        // Boolean column: $user->forceFill(['is_admin' => true])->save();
        $user->assignRole('admin');

        $this->info("Admin user {$email} is ready.");

        return Command::SUCCESS;
    }
}
