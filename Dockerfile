FROM php:7.4-fpm-alpine

# Install required packages.
RUN apk add --update --no-cache \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev \
    autoconf \
    g++ \
    make

# Install PHP extensions.
RUN docker-php-ext-install pdo_mysql gd bcmath mysqli zip exif

# Install PHP Redis.
RUN docker-php-source extract && \
    pecl install redis && \
    docker-php-ext-enable redis && \
    docker-php-source delete

# Remove packages only required for building.
RUN apk del g++ make