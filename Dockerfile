ARG PHP_VERSION=7.4

FROM php:${PHP_VERSION}-fpm

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# Install required PHP extensions for GExtension
RUN install-php-extensions mysqli bcmath zip curl ssh2
