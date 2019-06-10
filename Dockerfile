FROM php:7.2-fpm-alpine

RUN apk add --update --no-cache \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev

RUN docker-php-ext-configure gd --with-freetype-dir=/usr/include/ --with-png-dir=/usr/include/ --with-jpeg-dir=/usr/include/
RUN docker-php-ext-configure zip --with-libzip

RUN docker-php-ext-install pdo_mysql gd bcmath mysqli zip