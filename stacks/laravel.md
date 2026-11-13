# Appdonia - platform deployment: Laravel

Templates are in `templates/laravel/`:

| Template               | Goes to                                    | When                                        |
|------------------------|--------------------------------------------|---------------------------------------------|
| `appdonia.yaml`        | `docker/appdonia.yaml`                     | always                                      |
| `docker-entrypoint.sh` | `docker-entrypoint.sh` (repository root)   | only if the project has no entrypoint       |
| `Dockerfile`           | `Dockerfile` (repository root)             | only if the project has no Dockerfile       |
| `gitlab-ci.yml`        | `.gitlab-ci.yml` (repository root)         | only if no CI job builds and pushes the image |
| `EnsureAdminUser.php`  | `app/Console/Commands/EnsureAdminUser.php` | only if nothing creates the admin from env  |
| `SeedIfNeeded.php`     | `app/Console/Commands/SeedIfNeeded.php`    | only if seeding is not already run-once     |

The templates use placeholder names (`app`, `<business>`, `<project>`,
port 8000, `/var/www`). Replace every one of them with what the project
actually uses; if the project's image serves on another port or lives in
another directory, the yaml follows the project, not the template.

## 1. Inspect the project

Find out the following before writing anything. Each answer changes the output.

| Question | Where to look | Affects |
|---|---|---|
| Project name and repository URL | git remote, folder name, `composer.json`, `README` | header, `<project>` in the image URL, service names |
| Laravel version | `composer.lock` (`laravel/framework`) | health route (`/up` exists from Laravel 11) |
| Is `laravel/octane` installed? | `composer.json` | how the web server starts |
| Database driver | `config/database.php` default, `.env.example` | `mariadb` or `postgres` service, PHP extensions |
| Queue, cache, session drivers | `.env.example`, `config/*.php`, `laravel/horizon` | whether Redis is needed |
| Scheduled tasks | `routes/console.php`, `app/Console/Kernel.php` | `RUN_SCHEDULER` |
| Where uploads are written | `config/filesystems.php`, `public/uploads`, `storage/app/public` | volumes |
| How is an admin identified? | `User` model, roles package, `is_admin` column, seeders | `EnsureAdminUser.php` |
| Does a seeder create required data? | `database/seeders` | `SeedIfNeeded.php` |
| Is there an install wizard? | routes/controllers named `install`, middleware checking an "installed" flag | must be bypassed or removed |
| Does the app write settings to `.env`? | search for writes to `base_path('.env')`, env-editor packages | `.env` in the storage volume |
| Existing Docker setup | `Dockerfile`, `docker-entrypoint.sh`, `docker-compose*.yml`, `.dockerignore` | adapt instead of replace |
| Frontend build | `package.json`, `vite.config.js` | asset build in the Dockerfile |
| A public route that returns 200 without login | `routes/web.php` | healthcheck |

## 2. docker-entrypoint.sh

If the project has an entrypoint, read it and compare it with the behaviour
below. Change only what is missing or wrong, keep its project-specific steps,
and keep its command names (then use those names in `command:` in the yaml).
If it has none, start from the template.

The template takes one argument, the role:

- `web` (default): prepares the app, then runs the web server. Also starts the
  queue worker and scheduler in the background unless `RUN_QUEUE_WORKER` or
  `RUN_SCHEDULER` is `false`.
- `queue`, `scheduler`: run only that process. They exist so a deployment can
  be split into several containers later; the default template does not use
  them.
- anything else is executed as-is (`php artisan ...`, `sh`).

Only the `web` role migrates and seeds, so two containers never race on the
schema.

What the `web` role does, in order. Keep the order:

1. Creates the writable directories and fixes ownership. Volumes arrive empty
   on the first deploy and are owned by root.
2. Sets up `.env`. Real environment variables always win over the file. The
   file lives in the storage volume (`storage/.env`, symlinked to `.env`) so
   settings the app writes there survive redeploys. If the app never writes to
   `.env`, the block can stay; it is harmless.
3. Resolves `APP_KEY`: uses the variable from `appdonia.yaml`; if empty,
   generates one once and keeps it in the storage volume. The key must never
   change between deploys, or sessions and encrypted data are lost.
4. Deletes a stale `bootstrap/cache/config.php` so new variables are seen.
5. Waits for the database (bounded retries, then continues so the logs show
   the real error).
6. `php artisan migrate --force`.
7. `php artisan db:seed-if-needed` (seeds an empty database only).
8. `php artisan app:ensure-admin`.
9. `php artisan storage:link`, then caches config, routes and views.
10. Starts the background queue worker and scheduler, then `exec`s the web
    server so it receives stop signals.

Rules when adapting:

- Setup steps must not abort the boot. Each one logs its failure and the script
  continues, so the web server still starts and the cause is visible in the
  logs. Do not add `set -e`.
- Background processes run in a restart loop: `queue:work` exits by design
  after `--max-time`.
- Remove any installer hand-off: "installed" flag files, redirects to
  `/install`, licence prompts. If the app's middleware checks for a marker
  file, create that file in the entrypoint.
- Add project-specific steps (module migrations, translation imports, search
  indexes) after the migration step, each with `|| echo "... failed"`.

### Web server

The template picks the server in this order:

1. `laravel/octane` installed: `php artisan octane:start --server=frankenphp`.
2. `frankenphp` binary present: `frankenphp php-server --root public`.
3. Otherwise `php artisan serve`, with a warning. This is not a production
   server; use it only as a stopgap and tell the user.

If the project already ships an image with its own server (for example nginx
and php-fpm under supervisord), keep that server: replace the final `exec` in
the `web` role with the project's start command and leave the rest of the
entrypoint as it is.

Under Octane the application stays in memory. Do not add Octane to a project
that does not already use it; that is an application change, not a deployment
change.

## 3. Console commands

**`app:ensure-admin`** creates the first admin from `ADMIN_EMAIL`,
`ADMIN_PASSWORD` and `ADMIN_NAME`. Adapt the two marked places to the project:
how to tell that an admin already exists, and how to make a user an admin
(role package, `is_admin` column, a `role` field). Keep these properties:

- reads the values with `getenv()` first, because `env()` returns `null` once
  the config is cached;
- does nothing if the email or password is empty;
- does nothing if an admin already exists, and never changes a password.

**`db:seed-if-needed`** runs `db:seed --force` only when the database is still
empty. Adapt the emptiness check to a table the seeders always fill. If the
project's seeders create a default admin with a known password, remove that
from the seeder: the admin must come from `app:ensure-admin` only.

If the project already has equivalent commands, use them and update the
entrypoint to call them.

## 4. Dockerfile

If the project has a working `Dockerfile`, keep it and check only these points:

- Dependencies and frontend assets are built into the image
  (`composer install --no-dev`, `npm run build`). Nothing is downloaded or
  compiled at container start.
- `docker-entrypoint.sh` is copied in, executable, set as `ENTRYPOINT`, with
  `CMD ["web"]`.
- `curl` is installed (the healthcheck uses it), and `procps` if a healthcheck
  uses `pgrep`.
- The PHP extensions match the database driver (`pdo_mysql` or `pdo_pgsql`),
  plus `pcntl` for queue workers and Octane.
- `.dockerignore` excludes `.env`, `node_modules`, `vendor` and `.git`, and
  does not exclude `docker-entrypoint.sh`. It may exclude the `docker` folder:
  `docker/appdonia.yaml` is read by Appdonia, not by the image.

If there is none, create it from the template.

### Building the image

The image is built by GitLab CI in the project's repository and pushed to that
repository's container registry, which is the URL `docker/appdonia.yaml` uses.

- No `.gitlab-ci.yml`: create it from the `gitlab-ci.yml` template.
- A `.gitlab-ci.yml` without an image build: add the template's `build` stage
  and `build-image` job to it, keeping the existing jobs.
- One that already builds and pushes to `$CI_REGISTRY_IMAGE`: leave it alone.

The job tags `latest` from the default branch and `x.y.z` from `vx.y.z` git
tags. It uses `$CI_REGISTRY_IMAGE`, so it needs no edits when the business or
project name changes.

## 5. docker/appdonia.yaml

Start from the template and adapt:

- **Paths and port**: the container paths in `volumes:` and the port in
  `SERVICE_URL_<NAME>_<port>`, the `port` header and the healthcheck must be
  the ones the project's image really uses.
- **Command**: `command:` is the role name the project's entrypoint accepts
  for the web process. Omit it if the image's default `CMD` already does that.

- **Header**: `documentation` (public docs or repository URL), `slogan` (one
  sentence), `category`, `tags` (comma separated, lower case), `logo`, `port`.
- **Service name**: rename `app` to the product name in one lower-case word,
  and rename `SERVICE_URL_APP_8000` / `SERVICE_URL_APP` to match
  (`SERVICE_URL_<NAME>_8000`).
- **Image**: the literal URL
  `registry.gitlab.com/appdonia/<business>/<project>:latest`, with the
  business name the user gave and the project name taken from the project
  (see "Image name" in `SKILL.md`). No variable, no default syntax.
- **Database**: the template uses MariaDB. For PostgreSQL, swap the service
  (`postgres:16`, `POSTGRES_DB/USER/PASSWORD`, healthcheck
  `pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}`, volume at
  `/var/lib/postgresql/data`) and set `DB_CONNECTION=pgsql`, `DB_PORT=5432`.
- **Redis**: add a `redis:7-alpine` service (healthcheck `redis-cli ping`,
  volume at `/data`) only if the app requires it, for example Horizon or a
  Redis-only feature. Otherwise use `QUEUE_CONNECTION=database` and file
  cache and sessions, which need no extra service.
- **Volumes**: `storage` always. Add one volume per directory outside
  `storage` that the app writes user files to.
- **Healthcheck**: a route that returns 200 without authentication: `/up` on
  Laravel 11 and later, otherwise `/login` or `/`. Keep `start_period` long
  (300s): the first boot migrates and seeds before the server answers.
- **Environment**: keep only variables the app actually reads. Add
  product-specific ones the deployer should choose as `${NAME:-default}`.

Do not put mail, broadcasting or third-party API credentials in the file if
the app has a settings screen for them. Say so in the header comment, as the
template does.

`ADMIN_PASSWORD` is `${ADMIN_PASSWORD}`: the deployer sets it before the first
deploy. Mention in the header comment that no admin is created without it.

## 6. Validate

Run what the environment allows and report what you could not run:

```bash
sh -n docker-entrypoint.sh
```

```bash
docker compose -f docker/appdonia.yaml config -q
```

```bash
php -l app/Console/Commands/EnsureAdminUser.php
```

```bash
grep -rnE "ADAPT:|<business>|<project>" docker/appdonia.yaml docker-entrypoint.sh Dockerfile .gitlab-ci.yml app/Console/Commands
```

`docker compose config` warns that the `SERVICE_*` variables are not set. That
is expected; Appdonia generates them. Any other warning or error is real.

Then check by reading:

- [ ] no `build:`, `ports:`, `container_name:`, `networks:` or bind mounts
- [ ] the app `image:` is a literal
      `registry.gitlab.com/appdonia/<business>/<project>:latest`, lower case,
      with no `${...}` and no placeholder left in it
- [ ] every service has a healthcheck; `depends_on` uses `service_healthy`
- [ ] `SERVICE_URL_<NAME>_<port>` matches the service name and the port the
      server listens on, the `port` header and the healthcheck URL
- [ ] database credentials use the same `SERVICE_*` identifiers in the app and
      the database service
- [ ] every persistent directory is a named volume, declared under `volumes:`
- [ ] no secret, password or domain is written literally
- [ ] the entrypoint has no installer step and no `set -e`

If Docker is available and the user agrees, the real test is to build the
image and start the stack locally with the `SERVICE_*` variables supplied by
hand, then log in with the admin credentials.
