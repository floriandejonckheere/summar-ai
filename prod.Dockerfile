FROM ruby:3.4-alpine AS ruby

LABEL maintainer=Florian Dejonckheere <florian@floriandejonckheere.be>
LABEL org.opencontainers.image.source=https://github.com/floriandejonckheere/summar-ai

WORKDIR /app

# Install system dependencies
RUN apk add --no-cache build-base curl-dev git postgresql-dev cmake yaml-dev tzdata postgresql vips graphviz

# Install Bundler
RUN gem update --system && gem install bundler

# Install Gem dependencies
ADD Gemfile /app
ADD Gemfile.lock /app
ADD .ruby-version /app

RUN bundle config set --local without "development test" && \
    bundle config set --local jobs 4 && \
    bundle config set --local deployment true && \
    bundle install

FROM ruby AS node

# Install Yarn
RUN apk add --no-cache nodejs-current

# Enable corepack
RUN corepack enable

# Install NPM dependencies
ADD package.json /app
ADD yarn.lock /app

RUN yarn install

FROM node AS assets

# Install development dependencies
RUN bundle config set --local without "test" && \
    bundle config set --local deployment false && \
    bundle install

# Only add files that affect the assets:precompile task
ADD Rakefile                                /app/Rakefile
ADD tailwind.config.js                      /app/tailwind.config.js
ADD webpack.config.js                       /app/webpack.config.js
ADD config/application.rb                   /app/config/application.rb
ADD config/boot.rb                          /app/config/boot.rb
ADD config/environment.rb                   /app/config/environment.rb
ADD config/environments/production.rb       /app/config/environments/production.rb
ADD config/locales                          /app/config/locales
ADD app/views                               /app/app/views
ADD app/assets                              /app/app/assets

ARG SECRET_KEY_BASE=secret_key_base
ARG RAILS_ENV=production
ARG NODE_ENV=production

# Compile Rails assets
RUN rake assets:precompile

FROM ruby

ENV LC_ALL=en_US.UTF-8
ENV LANG=en_US.UTF-8

WORKDIR /app

# Add user
ARG USER=docker
ARG UID=1000
ARG GID=1000

RUN addgroup -g $GID $USER
RUN adduser -D -u $UID -G $USER -h /app/ $USER

# Add application
ADD . /app

# Copy assets
COPY --from=assets /app/public/ /app/public/

RUN mkdir -p /app/tmp/pids/
RUN chown -R $UID:$GID /app/

# Change user
USER $USER

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
