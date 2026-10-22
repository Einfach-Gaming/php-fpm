#!/usr/bin/env bash
# Smoke test for a locally available image: ./tests/smoke-test.sh <image>
set -euo pipefail

image="${1:?usage: $0 <image>}"
required_extensions=(ctype dom exif fileinfo gd gmp intl libxml mbstring openssl PDO pdo_mysql redis zlib "Zend OPcache")

run() { docker run --rm "$image" "$@"; }

echo "==> PHP version"
run php -v

echo "==> Required extensions"
modules="$(run php -m)"
missing=0
for ext in "${required_extensions[@]}"; do
  if ! grep -qxF "$ext" <<<"$modules"; then
    echo "missing extension: $ext" >&2
    missing=1
  fi
done
[ "$missing" -eq 0 ]

echo "==> GD WebP support"
run php -r 'exit(gd_info()["WebP Support"] ? 0 : 1);'

echo "==> 64-bit integers"
run php -r 'exit(PHP_INT_SIZE === 8 ? 0 : 1);'

echo "==> Runs as non-root"
[ "$(run id -u)" != "0" ]

echo "==> Production settings"
run php -r 'exit(ini_get("expose_php") || ini_get("display_errors") ? 1 : 0);'

echo "==> php-fpm config test"
run php-fpm -t

echo "==> php-fpm answers ping"
container="$(docker run -d --read-only --tmpfs /tmp "$image")"
trap 'docker logs "$container"; docker rm -f "$container" >/dev/null' EXIT
for _ in $(seq 1 20); do
  if docker exec "$container" php-fpm-healthcheck; then
    echo "smoke test passed"
    exit 0
  fi
  sleep 1
done
echo "php-fpm did not become healthy" >&2
exit 1
