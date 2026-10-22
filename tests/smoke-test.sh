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

echo "==> php-fpm starts as 1001:1001 with read-only root"
container="$(docker run -d \
  --user 1001:1001 \
  --read-only \
  --tmpfs /tmp:rw,nosuid,nodev,size=64m,mode=1777 \
  --env PHP_MEMORY_LIMIT=192M \
  --env PHP_UPLOAD_MAX_FILESIZE=3M \
  --env PHP_POST_MAX_SIZE=4M \
  --env PHP_MAX_EXECUTION_TIME=17 \
  --env PHP_OPCACHE_MEMORY_CONSUMPTION=64 \
  --env PHP_OPCACHE_MAX_ACCELERATED_FILES=10000 \
  --env FPM_PM=dynamic \
  --env FPM_PM_MAX_CHILDREN=7 \
  --env FPM_PM_START_SERVERS=2 \
  --env FPM_PM_MIN_SPARE_SERVERS=1 \
  --env FPM_PM_MAX_SPARE_SERVERS=3 \
  --env FPM_PM_MAX_REQUESTS=123 \
  --env FPM_HEALTHCHECK_ADDRESS=localhost:9000 \
  "$image")"
trap 'docker logs "$container"; docker rm -f "$container" >/dev/null' EXIT
[ "$(docker exec "$container" id -u)" = "1001" ]
[ "$(docker exec "$container" id -g)" = "1001" ]

for _ in $(seq 1 20); do
  if docker exec "$container" php-fpm-healthcheck; then
    break
  fi
  sleep 1
done
docker exec "$container" php-fpm-healthcheck

echo "==> FPM environment overrides"
fpm_config="$(docker exec "$container" php-fpm -tt 2>&1)"
for setting in \
  "pm = dynamic" \
  "pm.max_children = 7" \
  "pm.start_servers = 2" \
  "pm.min_spare_servers = 1" \
  "pm.max_spare_servers = 3" \
  "pm.max_requests = 123"; do
  if ! grep -Fq "$setting" <<<"$fpm_config"; then
    echo "missing FPM override: $setting" >&2
    echo "$fpm_config" >&2
    exit 1
  fi
done

echo "==> FastCGI PHP overrides and session temp path"
docker exec -i --user 1001:1001 "$container" sh -c 'cat > /tmp/php-fpm-smoke.php' <<'PHP'
<?php
$expected = [
    'PHP_MEMORY_LIMIT' => 'memory_limit',
    'PHP_UPLOAD_MAX_FILESIZE' => 'upload_max_filesize',
    'PHP_POST_MAX_SIZE' => 'post_max_size',
    'PHP_MAX_EXECUTION_TIME' => 'max_execution_time',
    'PHP_OPCACHE_MEMORY_CONSUMPTION' => 'opcache.memory_consumption',
    'PHP_OPCACHE_MAX_ACCELERATED_FILES' => 'opcache.max_accelerated_files',
];
$upload_dir = ini_get('upload_tmp_dir') ?: sys_get_temp_dir();

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    foreach ($expected as $variable => $setting) {
        if (ini_get($setting) !== getenv($variable)) {
            http_response_code(500);
            exit("override mismatch: $variable\n");
        }
    }
    $session_dir = session_save_path() ?: sys_get_temp_dir();
    $session_dir = session_save_path() ?: sys_get_temp_dir();
    foreach (['session' => $session_dir, 'upload' => $upload_dir] as $name => $path) {
        if (!is_dir($path) || !is_writable($path)) {
            http_response_code(500);
            exit("$name temp path is not writable: $path\n");
        }
        $probe = tempnam($path, 'php-fpm-smoke-');
        if ($probe === false) {
            http_response_code(500);
            exit("$name temp path cannot create files: $path\n");
        }
        unlink($probe);
    }

    if (!session_start()) {
        http_response_code(500);
        exit("session could not start\n");
    }
    $_SESSION['smoke'] = 'ok';
    session_write_close();
    echo "SMOKE_FASTCGI_GET_OK\n";
    exit;
}

if ($_SERVER['REQUEST_METHOD'] === 'POST'
    && isset($_FILES['upload'])
    && $_FILES['upload']['error'] === UPLOAD_ERR_OK
    && realpath(dirname($_FILES['upload']['tmp_name'])) === realpath($upload_dir)
    && is_uploaded_file($_FILES['upload']['tmp_name'])
    && file_get_contents($_FILES['upload']['tmp_name']) === 'php-fpm upload smoke test') {
    echo "SMOKE_FASTCGI_UPLOAD_OK\n";
    exit;
}

http_response_code(500);
echo "FastCGI request validation failed\n";
PHP

fastcgi_env=(
  DOCUMENT_ROOT=/tmp
  GATEWAY_INTERFACE=CGI/1.1
  REMOTE_ADDR=127.0.0.1
  REMOTE_PORT=12345
  REQUEST_URI=/php-fpm-smoke.php
  SERVER_NAME=localhost
  SERVER_PORT=9000
  SERVER_PROTOCOL=HTTP/1.1
  SERVER_SOFTWARE=php-fpm-smoke
  SCRIPT_FILENAME=/tmp/php-fpm-smoke.php
  SCRIPT_NAME=/php-fpm-smoke.php
)
get_response="$(docker exec "$container" env "${fastcgi_env[@]}" REQUEST_METHOD=GET CONTENT_LENGTH=0 \
  cgi-fcgi -bind -connect 127.0.0.1:9000)"
if ! grep -Fq "SMOKE_FASTCGI_GET_OK" <<<"$get_response"; then
  echo "$get_response" >&2
  exit 1
fi

boundary="php-fpm-smoke-boundary"
body="$(printf '%s\r\n' \
  "--$boundary" \
  'Content-Disposition: form-data; name="upload"; filename="smoke.txt"' \
  'Content-Type: text/plain' \
  '' \
  'php-fpm upload smoke test' \
  "--$boundary--")"
content_length="$(printf %s "$body" | wc -c | tr -d ' ')"
upload_response="$(printf %s "$body" | docker exec -i "$container" env "${fastcgi_env[@]}" \
  REQUEST_METHOD=POST \
  CONTENT_TYPE="multipart/form-data; boundary=$boundary" \
  CONTENT_LENGTH="$content_length" \
  cgi-fcgi -bind -connect 127.0.0.1:9000)"
if ! grep -Fq "SMOKE_FASTCGI_UPLOAD_OK" <<<"$upload_response"; then
  echo "$upload_response" >&2
  exit 1
fi

echo "smoke test passed"
