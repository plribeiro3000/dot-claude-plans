# Source: https://raw.githubusercontent.com/rails/rails/main/railties/lib/rails/generators/rails/app/templates/Dockerfile.tt
# Fetched: 2026-08-06
# This is the Dockerfile template Rails itself generates via `rails new` (Rails 7.1+).
# Preserved verbatim (ERB template syntax kept as fetched) for reference — this is the
# primary evidence that Rails' own generator does not pin a Bundler version anywhere.

# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t <%= app_name %> .
# docker run -d -p 80:<%= skip_thruster? ? 3000 : 80 %> -e RAILS_MASTER_KEY=<value from config/master.key> --name <%= app_name %> <%= app_name %>

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=<%= Gem.ruby_version %>
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y <%= dockerfile_base_packages.join(" ") %> && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems (and node modules, conditional)
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y <%= dockerfile_build_packages.join(" ") %> && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# [node/bun install blocks omitted here — not relevant to bundler version]

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    # [rest of RUN chain omitted in this excerpt — the load-bearing fact is that
    #  no ARG BUNDLER_VERSION, ENV BUNDLER_VERSION, or `gem install bundler -v ...`
    #  line exists anywhere in the template before this `bundle install` call.]

# NOTE ON WHAT THIS PROVES:
# - ARG RUBY_VERSION exists (mirrors 4Shark's own ARG RUBY_VERSION pattern).
# - There is NO equivalent ARG/ENV for Bundler anywhere in the file.
# - The only bundler invocation is the bare `bundle install` — which means
#   whatever bundler the base ruby:$RUBY_VERSION-slim image ships as its
#   default gem is what runs, and Bundler's own BUNDLED-WITH auto-switch
#   (see quotes file) is what reconciles it against Gemfile.lock, not the
#   Dockerfile author.
