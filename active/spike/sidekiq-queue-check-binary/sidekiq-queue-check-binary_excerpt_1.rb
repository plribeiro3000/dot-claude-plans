# Auxiliary — lib/sidekiq/api.rb excerpts, PINNED at tag v8.0.10
#
# Source: https://raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb
# Pinned to v8.0.10 because that is the exact gem version `app` runs
# (~/Projects/4Shark/app/Gemfile.lock:665 — "sidekiq (8.0.10)").
#
# Verification method: the pinned-tag file was downloaded fresh for this revision
#   curl -s https://raw.githubusercontent.com/sidekiq/sidekiq/v8.0.10/lib/sidekiq/api.rb -o /tmp/sidekiq_api_v8010.rb
# (1348 lines, confirmed with `wc -l`) and every line number below was read out of
# that local file with `grep -n` / a ranged `Read`, never by asking a fetch tool
# "is <substring> at line N?" (see SPIKE.md § Citation method — a prior revision
# got this wrong three times doing exactly that).

# =============================================================================
# 1) Sidekiq::Stats#fetch_stats_slow! (lines 134-157) — THE authoritative
#    implementation of both aggregates the engineer's binary needs: total
#    queue depth ("enqueued") and total busy count ("workers_size"), each
#    summed across every queue/process member in ONE pipelined round trip.
# =============================================================================
#    134     def fetch_stats_slow!
#    135       processes = Sidekiq.redis { |conn|
#    136         conn.sscan("processes").to_a
#    137       }
#    138
#    139       queues = Sidekiq.redis { |conn|
#    140         conn.sscan("queues").to_a
#    141       }
#    142
#    143       pipe2_res = Sidekiq.redis { |conn|
#    144         conn.pipelined do |pipeline|
#    145           processes.each { |key| pipeline.hget(key, "busy") }
#    146           queues.each { |queue| pipeline.llen("queue:#{queue}") }
#    147         end
#    148       }
#    149
#    150       s = processes.size
#    151       workers_size = pipe2_res[0...s].sum(&:to_i)
#    152       enqueued = pipe2_res[s..].sum(&:to_i)
#    153
#    154       @stats[:workers_size] = workers_size
#    155       @stats[:enqueued] = enqueued
#    156       @stats
#    157     end
#
# Line numbers confirmed by `grep -n "def fetch_stats_slow!\|workers_size = pipe2_res\|enqueued = pipe2_res"`.

# =============================================================================
# 2) Sidekiq::Stats#queues (lines 66-79) — per-queue breakdown, same
#    primitives (SSCAN "queues" + pipelined LLEN), sorted descending by size
# =============================================================================
#     66     def queues
#     67       Sidekiq.redis do |conn|
#     68         queues = conn.sscan("queues").to_a
#     69
#     70         lengths = conn.pipelined { |pipeline|
#     71           queues.each do |queue|
#     72             pipeline.llen("queue:#{queue}")
#     73           end
#     74         }
#     75
#     76         array_of_arrays = queues.zip(lengths).sort_by { |_, size| -size }
#     77         array_of_arrays.to_h
#     78       end
#     79     end
#
# Class-level accessors calling into the aggregates above (lines 25, 50, 58):
#     25   class Stats
#     50     def enqueued
#     58     def workers_size
# Both are backed by `fetch_stats_slow!`'s summed values (confirmed by reading
# lines 30-60 in full — each is a thin `stat :name` accessor over the @stats hash).

# =============================================================================
# 3) Sidekiq::Stats#fetch_stats_fast! (lines 83-94) — O(1) pipeline for the
#    OTHER stats (processed/failed/scheduled/retry/dead/processes_size); not
#    needed by the engineer's binary, included for completeness on what
#    Sidekiq itself treats as "fast" vs "slow" (queue+busy sums are "slow").
# =============================================================================
#     83     def fetch_stats_fast!
#     84       pipe1_res = Sidekiq.redis { |conn|
#     85         conn.pipelined do |pipeline|
#     86           pipeline.get("stat:processed")
#     87           pipeline.get("stat:failed")
#     88           pipeline.zcard("schedule")
#     89           pipeline.zcard("retry")
#     90           pipeline.zcard("dead")
#     91           pipeline.scard("processes")
#     92           pipeline.lindex("queue:default", -1)
#     93         end
#     94       }

# =============================================================================
# 4) Sidekiq::Queue#initialize / #size (lines 250-261) — the LLEN-backed
#    primitive every queue-depth read above builds on
# =============================================================================
#    250     def initialize(name = "default")
#    251       @name = name.to_s
#    252       @rname = "queue:#{name}"
#    253     end
#    ...
#    259     def size
#    260       Sidekiq.redis { |con| con.llen(@rname) }
#    261     end
#
# Sidekiq::Queue.all (lines 243-245) confirms "queues" is read via SSCAN — a
# Set-scan command — so it is a Redis SET (not a Hash or Sorted Set):
#    243     def self.all
#    244       Sidekiq.redis { |c| c.sscan("queues").to_a }.sort.map { |q| Sidekiq::Queue.new(q) }
#    245     end

# =============================================================================
# 5) Sidekiq::ProcessSet.[] and #each (lines 924-949, 986-1012) — the "busy"
#    field per process, read via HMGET/HGET on the process's own identity key
# =============================================================================
#    924   ##
#    925   # Enumerates the set of Sidekiq processes which are actively working
#    926   # right now.  Each process sends a heartbeat to Redis every 5 seconds
#    927   # so this set should be relatively accurate, barring network partitions.
#    931   class ProcessSet
#    ...
#    934     def self.[](identity)
#    935       exists, (info, busy, beat, quiet, rss, rtt_us) = Sidekiq.redis { |conn|
#    936         conn.multi { |transaction|
#    937           transaction.sismember("processes", identity)
#    938           transaction.hmget(identity, "info", "busy", "beat", "quiet", "rss", "rtt_us")
#    939         }
#    940       }
#    ...
#    986     def each
#    987       result = Sidekiq.redis { |conn|
#    988         procs = conn.sscan("processes").to_a.sort
#    989
#    990         # We're making a tradeoff here between consuming more memory instead of
#    991         # making more roundtrips to Redis, but if you have hundreds or thousands of workers,
#    992         # you'll be happier this way
#    993         conn.pipelined do |pipeline|
#    994           procs.each do |key|
#    995             pipeline.hmget(key, "info", "busy", "beat", "quiet", "rss", "rtt_us")
#    996           end
#    997         end
#    998       }
#    999
#    1000      result.each do |info, busy, beat, quiet, rss, rtt_us|
#    ...
#    1007        yield Process.new(hash.merge("busy" => busy.to_i,
#
# Every live Sidekiq process registers its identity into the Redis SET named
# "processes"; the per-process Redis key IS the process identity string
# itself (a Redis HASH with an "info"/"busy"/"beat"/... field set). "busy" is
# the field the engineer's binary sums for the "currently executing" signal.
