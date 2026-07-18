# Auxiliary — internal `app` Ruby excerpts cited in SPIKE.md
# Preserved verbatim from ~/Projects/4Shark/app/lib/application_configuration.rb.
#
# NOTE ON SCOPE: this revision of the spike DOES NOT cite Computation/Counter
# (app/app/models/computation.rb, counter.rb) — the engineer has explicitly
# rejected the Computation counters as a signal for this binary (there is one
# Computation per commission; checking thousands of keys at deploy-check time
# is infeasible). A prior revision of this spike cited them; this revision
# drops that citation entirely, per instruction.

# =============================================================================
# lib/application_configuration.rb:136-155 — Sidekiq client/server Redis
# config, confirms TLS with certificate verification disabled
# =============================================================================
#    136     def sidekiq_client
#    137       config =
#    138         {
#    139           url: redis_sidekiq_url,
#    140           size: puma_workers * (puma_threads / 2),
#    141           ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
#    142           connect_timeout: redis_connect_timeout,
#    143           read_timeout: redis_read_timeout,
#    144           write_timeout: redis_write_timeout
#    145         }
#    146
#    147       config[:reconnect_attempts] = redis_reconnect_attempts if redis_reconnect_attempts.present?
#    148
#    149       if redis_sentinels.present?
#    150         config[:sentinels] = redis_sentinels
#    151         config[:failover_reconnect_timeout] = 20
#    152       end
#    153
#    154       config
#    155     end
#    156
#    157     def sidekiq_server
#    158       config =
#    159         {
#    160           url: redis_sidekiq_url,
#    161           size: sidekiq_threads + 5,
#    162           ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE },
#    163           connect_timeout: redis_connect_timeout,
#    164           read_timeout: redis_read_timeout,
#    ...

# =============================================================================
# lib/application_configuration.rb:303-317 — the URL resolution chain,
# confirming redis_sidekiq_url FALLS BACK to redis_url (which is REDIS_URL)
# when REDIS_SIDEKIQ_URL is not set. This is exactly what beta-001/demo-001
# rely on (they have no REDIS_SIDEKIQ_URL SSM parameter — see excerpt_2.tf).
# =============================================================================
#    303     def redis_url
#    304       if dummy_configuration?
#    305         'redis://localhost:6379'
#    306       else
#    307         ENV.fetch('REDIS_URL')
#    308       end
#    309     end
#    310
#    311     def redis_cache_url
#    312       ENV.fetch('REDIS_CACHE_URL', redis_url)
#    313     end
#    314
#    315     def redis_sidekiq_url
#    316       ENV.fetch('REDIS_SIDEKIQ_URL', redis_url)
#    317     end
#
# Read directly this revision (offset 290-330); lines re-confirmed unchanged
# from the prior revision's citation.
