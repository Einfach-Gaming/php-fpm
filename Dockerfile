# syntax=docker/dockerfile:1

# PHP minor version to build. WoltLab Suite 6.1 supports PHP 8.1 - 8.3, PHP 8.4 requires WoltLab Suite 6.2+.
ARG PHP_VERSION=8.3
ARG DEBIAN_RELEASE=bookworm

FROM mlocati/php-extension-installer:2.12.3 AS php-extension-installer

FROM php:${PHP_VERSION}-fpm-${DEBIAN_RELEASE}

# Install all OS security updates that are not yet part of the upstream base image.
# libfcgi-bin provides cgi-fcgi, used by the php-fpm-healthcheck script.
RUN apt-get update \
    && apt-get upgrade -y --no-install-recommends \
    && apt-get install -y --no-install-recommends libfcgi-bin \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions required/recommended by WoltLab Suite 6.1 (https://manual.woltlab.com/en/requirements/)
# that are not already part of the official image (ctype, dom, fileinfo, libxml, mbstring, openssl, pdo, zlib,
# opcache are built in). gd is built with WebP support by install-php-extensions.
RUN --mount=type=bind,from=php-extension-installer,source=/usr/bin/install-php-extensions,target=/usr/local/bin/install-php-extensions \
    install-php-extensions exif gd gmp intl pdo_mysql redis \
    && rm -rf /tmp/* /var/lib/apt/lists/*

RUN cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

COPY rootfs/ /

# Runtime tuning, override via environment variables (e.g. in the Kubernetes deployment).
ENV PHP_MEMORY_LIMIT=256M \
    PHP_UPLOAD_MAX_FILESIZE=64M \
    PHP_POST_MAX_SIZE=64M \
    PHP_MAX_EXECUTION_TIME=60 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=128 \
    PHP_OPCACHE_MAX_ACCELERATED_FILES=20000 \
    FPM_PM=dynamic \
    FPM_PM_MAX_CHILDREN=20 \
    FPM_PM_START_SERVERS=4 \
    FPM_PM_MIN_SPARE_SERVERS=2 \
    FPM_PM_MAX_SPARE_SERVERS=6 \
    FPM_PM_MAX_REQUESTS=1000

# Run php-fpm master and workers as an unprivileged user (www-data, uid/gid 33).
USER 33:33

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["php-fpm-healthcheck"]
