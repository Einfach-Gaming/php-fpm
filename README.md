# php-fpm

Custom php-fpm build used for the PHP web services at Einfach Gaming (WoltLab Suite forum, loading screen, ...).

Based on the official `php:<version>-fpm-bookworm` image with:

- all PHP extensions required by [WoltLab Suite](https://manual.woltlab.com/en/requirements/) (`exif`, `gd` with WebP, `gmp`, `intl`, `pdo_mysql`, plus the built-in `ctype`, `dom`, `fileinfo`, `libxml`, `mbstring`, `openssl`, `pdo`, `zlib`, `opcache`) and the recommended `redis` extension
- `php.ini-production` with hardened overrides (`expose_php=Off`, secure session cookies, OPcache)
- php-fpm running as non-root user `www-data` (uid/gid `33`), compatible with a read-only root filesystem (only `/tmp` needs to be writable)
- FPM `ping`/`status` endpoints and a `php-fpm-healthcheck` command for liveness/readiness probes

## Tags

Images are published to `ghcr.io/einfach-gaming/php-fpm` for `linux/amd64` and `linux/arm64`.

| Tag | Example | Behaviour |
|---|---|---|
| `<minor>` | `8.3` | Moving, always the latest build of that PHP minor version |
| `<patch>` | `8.3.27` | Moving, latest build of that PHP patch version |
| `<patch>-<date>-<sha>-<run-id>-<run-attempt>` | `8.3.27-20261022-0aa3171-39724048089-1` | Immutable, use this (or the digest) in deployments |

PHP `8.3` is used for WoltLab Suite 6.1 (PHP 8.4 requires WoltLab Suite 6.2+). PHP `8.4` is available for other apps.

Images are rebuilt daily without cache to pick up PHP patch releases and Debian security updates, and on every push to `main`. CI tests FPM under UID/GID `1001:1001` with a read-only root filesystem and writable `/tmp`, validates FastCGI requests and configuration overrides, and blocks publishing when fixable HIGH or CRITICAL vulnerabilities are found.
Every image ships with SBOM and provenance attestations and is signed with [cosign](https://github.com/sigstore/cosign) (keyless):

```sh
cosign verify ghcr.io/einfach-gaming/php-fpm:8.3 \
  --certificate-identity-regexp '^https://github.com/Einfach-Gaming/php-fpm/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Configuration

| Variable | Default |
|---|---|
| `PHP_MEMORY_LIMIT` | `256M` |
| `PHP_UPLOAD_MAX_FILESIZE` | `64M` |
| `PHP_POST_MAX_SIZE` | `64M` |
| `PHP_MAX_EXECUTION_TIME` | `60` |
| `PHP_OPCACHE_MEMORY_CONSUMPTION` | `128` |
| `PHP_OPCACHE_MAX_ACCELERATED_FILES` | `20000` |
| `FPM_PM` | `dynamic` |
| `FPM_PM_MAX_CHILDREN` | `20` |
| `FPM_PM_START_SERVERS` | `4` |
| `FPM_PM_MIN_SPARE_SERVERS` | `2` |
| `FPM_PM_MAX_SPARE_SERVERS` | `6` |
| `FPM_PM_MAX_REQUESTS` | `1000` |
| `FPM_HEALTHCHECK_ADDRESS` | `127.0.0.1:9000` (used by `php-fpm-healthcheck`) |

`/fpm-ping` and `/fpm-status` must not be exposed through the web server.

## Development

```sh
docker build --build-arg PHP_VERSION=8.3 -t php-fpm:test .
./tests/smoke-test.sh php-fpm:test
```

Dependencies (extension installer, GitHub Actions) are kept up to date by Renovate with automerge.
