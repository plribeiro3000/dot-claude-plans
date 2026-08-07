# Source: https://raw.githubusercontent.com/docker-library/ruby/master/4.0/bookworm/Dockerfile
# Fetched: 2026-08-06
# This is the CURRENT official docker-library/ruby Dockerfile for the 4.0/bookworm
# tag family (which produces `ruby:4.0.6` and `ruby:4.0-bookworm`, the base image
# family the four 4Shark repos use). Preserved verbatim as fetched.
# Load-bearing fact: there is NO `ENV BUNDLER_VERSION` line and NO
# `gem install bundler` line anywhere in this file. Ruby is built from source and
# whatever bundler ships as Ruby's own default gem (per ruby/ruby's
# tool/sync_default_gems.rb, synced from the bundler/bundler repo at Ruby release
# time) is what ends up in the image. The final smoke test is a bare
# `bundle --version` with no version argument.

#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY
#

FROM buildpack-deps:bookworm

# skip installing gem documentation with `gem install`/`gem update`
RUN set -eux; \
	mkdir -p /usr/local/etc; \
	echo 'gem: --no-document' >> /usr/local/etc/gemrc

ENV LANG C.UTF-8

# https://www.ruby-lang.org/en/news/2026/07/14/ruby-4-0-6-released/
ENV RUBY_VERSION 4.0.6
ENV RUBY_DOWNLOAD_URL https://cache.ruby-lang.org/pub/ruby/4.0/ruby-4.0.6.tar.xz
ENV RUBY_DOWNLOAD_SHA256 9c9d121fe3314ea7c801e690b9de981d2b9d12d7849db99c27482468a541ba0a

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		dpkg-dev \
		libgdbm-dev \
		ruby \
	; \
	\
	[... rustup toolchain setup for YJIT/ZJIT, omitted, not relevant to bundler ...] \
	\
	wget -O ruby.tar.xz "$RUBY_DOWNLOAD_URL"; \
	echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict; \
	\
	mkdir -p /usr/src/ruby; \
	tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
	rm ruby.tar.xz; \
	\
	cd /usr/src/ruby; \
	\
	autoconf; \
	gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
	./configure \
		--build="$gnuArch" \
		--disable-install-doc \
		--enable-shared \
		${rustArch:+--enable-yjit} \
		${rustArch:+--enable-zjit} \
	; \
	make -j "$(nproc)"; \
	make install; \
	\
	[... cleanup steps omitted ...] \
	\
	cd /; \
	rm -r /usr/src/ruby; \
# verify we have no "ruby" packages installed
	if dpkg -l | grep -i ruby; then exit 1; fi; \
	[ "$(command -v ruby)" = '/usr/local/bin/ruby' ]; \
# rough smoke test
	ruby --version; \
	gem --version; \
	bundle --version

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
	BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH
RUN set -eux; \
	mkdir "$GEM_HOME"; \
# adjust permissions of GEM_HOME for running "gem install" as an arbitrary user
	chmod 1777 "$GEM_HOME"

CMD [ "irb" ]
