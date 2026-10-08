#!/bin/sh
# Runs the append statements of every strategy through pgbench on the database host, which takes
# the client network out of commit latency. Needs the outbox_bench schema that
# bench/outbox_bench.exs installs, and pgbench on the database host. merge needs Postgres 17 for
# MERGE ... RETURNING.
#
#     docker cp bench/. postgres:/tmp/outbox_bench && \
#       docker exec postgres sh /tmp/outbox_bench/pgbench.sh trogon_outbox_bench on
set -eu

database=$1
synchronous_commit=${2:-on}
seconds=${PGBENCH_SECONDS:-5}
writer_counts=${PGBENCH_WRITERS:-1 8 64}
dir=$(dirname "$0")
export PGOPTIONS="-c synchronous_commit=$synchronous_commit"

echo "| strategy | writers | sources | commits/s | p50 ms | p99 ms |"
echo "| --- | --- | --- | --- | --- | --- |"

for strategy in counter merge advisory_lock; do
  for writers in $writer_counts; do
    for sources in same distinct; do
      if [ "$sources" = same ]; then spread=1; else spread=1000000; fi
      psql -qAt -U postgres -d "$database" \
        -c "TRUNCATE outbox_bench.outbox_events, outbox_bench.outbox_sources, outbox_bench.outbox_cursors"
      rm -rf "$dir/log" && mkdir -p "$dir/log"
      tps=$(cd "$dir/log" && pgbench -n -U postgres -M prepared -c "$writers" -j "$writers" -T "$seconds" \
        -D spread="$spread" -f "../pgbench_$strategy.sql" --log "$database" 2>/dev/null |
        sed -n 's/^tps = \([0-9.]*\).*/\1/p')
      cat "$dir"/log/pgbench_log.* | awk '{ print $3 }' | sort -n > "$dir/log/latencies"
      count=$(wc -l < "$dir/log/latencies")
      p50=$(sed -n "$(( (count + 1) / 2 ))p" "$dir/log/latencies")
      p99=$(sed -n "$(( (count * 99 + 99) / 100 ))p" "$dir/log/latencies")
      printf '| %s | %s | %s | %.0f | %.2f | %.2f |\n' "$strategy" "$writers" "$sources" "$tps" \
        "$(echo "$p50 / 1000" | bc -l)" "$(echo "$p99 / 1000" | bc -l)"
    done
  done
done
