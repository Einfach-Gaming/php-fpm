ARG PHP_VERSION=8.1

FROM php:${PHP_VERSION}-fpm

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# Install required PHP extensions
# https://manual.woltlab.com/en/requirements/
# mysqli and bcmath are only required by GExtension and can be removed in the future
RUN install-php-extensions ctype dom exif gmp intl libxml mbstring openssl pdo pdo_mysql zlib gd opcache

# Install required PHP extensions for GExtension
RUN install-php-extensions mysqli bcmath zip
