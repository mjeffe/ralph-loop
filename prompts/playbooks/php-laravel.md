# PHP / Laravel Playbook

## Runtime Installation

- Use the `ondrej/php` PPA to install the desired PHP version (e.g., `php8.3`).
- Install PHP as CLI + FPM: `php${VER}-cli`, `php${VER}-fpm`.
- Common extensions to install by default:
  `mbstring`, `xml`, `curl`, `zip`, `bcmath`, `intl`, `gd`, `readline`, `tokenizer`.
- Database extensions based on project config:
  `pdo_pgsql` / `pgsql` for PostgreSQL, `pdo_mysql` / `mysql` for MySQL/MariaDB.
- If the project uses Redis, install `php${VER}-redis`.

## Package Manager

- Install Composer from https://getcomposer.org (multi-line installer or `composer-setup.php`).
- Run `composer install --no-interaction --no-progress --optimize-autoloader`.

## Framework Bootstrap

After dependency install, run in order:

1. `cp .env.example .env` (if `.env` is missing)
2. `php artisan key:generate` (if `APP_KEY` is empty)
3. `php artisan migrate --force` (behind a sentinel check)
4. `php artisan db:seed --force` if seeders exist (behind a sentinel check).
   Check for `database/seeders/DatabaseSeeder.php` or equivalent. If the
   project has separate reference-data and dev-data seeders, seed both.
5. `php artisan storage:link` (idempotent, safe to re-run)
6. If `package.json` exists: `npm ci && npm run build` (behind a sentinel check)

## Workdir

Use `/var/www/html` as the project working directory.

## Sandbox .env Overrides

Apply these overrides in the sandbox `.env` to simplify the single-container setup:

- `QUEUE_CONNECTION=sync`
- `CACHE_STORE=file`
- `SESSION_DRIVER=file`
- `MAIL_MAILER=smtp` with `MAIL_HOST=127.0.0.1`, `MAIL_PORT=1025` (Mailpit)
- `DB_HOST=127.0.0.1`
- Set `DB_CONNECTION`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD`
  to match the provisioned database.

## Test Environment Bootstrapping

If `.env.testing` exists (or `.env.testing.example`):

1. Copy `.env.testing.example` → `.env.testing` if missing.
2. Populate empty secret keys (`APP_KEY`, `JWT_SECRET`, etc.) with generated
   values, same as the primary `.env`.
3. **Container env var conflict mitigation:** Laravel uses `Dotenv\Dotenv` in
   immutable mode — it will not overwrite env vars already present in `$_SERVER`
   or `$_ENV`. Since the entrypoint exports vars like `DB_DATABASE`, those leak
   into PHPUnit and override `.env.testing` values silently. To fix this, create
   or patch `tests/bootstrap.php` (or the file referenced by `phpunit.xml`
   `bootstrap=`) to clear conflicting vars before Laravel boots:

   ```php
   // Clear container-level DB env vars so .env.testing values take effect
   foreach (['DB_CONNECTION','DB_HOST','DB_PORT','DB_DATABASE','DB_USERNAME','DB_PASSWORD'] as $key) {
       putenv($key);
       unset($_ENV[$key], $_SERVER[$key]);
   }
   ```

   Place this **before** the `require __DIR__.'/../vendor/autoload.php'` line.

4. If `.env.testing` specifies a separate test database (e.g., `DB_DATABASE=myapp_testing`),
   create that database during the DB bootstrap step (entrypoint step 8).

## Long-Running Processes (supervisord)

Configure supervisord programs for:

- **php-fpm** or `php artisan serve --host=0.0.0.0 --port=80` (web server)
- **Database server** (PostgreSQL or MySQL, whichever is provisioned)
- **Vite dev server** (`npm run dev`), only if the project has a `vite.config.*`
- **Mailpit**, only if mail is provisioned
