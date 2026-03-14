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
4. `php artisan storage:link` (idempotent, safe to re-run)
5. If `package.json` exists: `npm ci && npm run build` (behind a sentinel check)

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

## Long-Running Processes (supervisord)

Configure supervisord programs for:

- **php-fpm** or `php artisan serve --host=0.0.0.0 --port=80` (web server)
- **Database server** (PostgreSQL or MySQL, whichever is provisioned)
- **Vite dev server** (`npm run dev`), only if the project has a `vite.config.*`
- **Mailpit**, only if mail is provisioned
