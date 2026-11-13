<?php

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

/**
 * Seeds the database on the first boot only, so the container entrypoint can
 * call it on every start.
 */
class SeedIfNeeded extends Command
{
    protected $signature = 'db:seed-if-needed';

    protected $description = 'Seed the database only if it has not been seeded yet';

    public function handle(): int
    {
        // ADAPT: a table the seeders always fill (roles, settings, plans, ...).
        // Don't use the users table if app:ensure-admin can run before seeding.
        if (DB::table('roles')->exists()) {
            $this->info('Database already seeded, skipping.');

            return Command::SUCCESS;
        }

        $this->info('Seeding database...');
        Artisan::call('db:seed', ['--force' => true], $this->output);
        $this->info('Database seeded.');

        return Command::SUCCESS;
    }
}
