#!/bin/zsh
# Record the app's peak RSS while an integration command runs. macOS ps
# reports RSS in KiB. Match the executable name, not the full command line:
# the sampler's own arguments contain the requested app path.
set -u
setopt NO_BG_NICE

if (( $# < 4 )); then
  print -u2 'usage: sample_app_peak_rss_macos.sh <output-dir> <app-executable> -- <command> [args...]'
  exit 64
fi

output_dir=$1
app_name=${2:t}
shift 2
if [[ $1 != -- ]]; then
  print -u2 'expected -- before the command'
  exit 64
fi
shift
mkdir -p "$output_dir" || exit
samples="$output_dir/rss-samples.tsv"
print 'sample\tpid\tprocess\trss_kib' > "$samples"

"$@" &
command_pid=$!
sample_number=0
while kill -0 "$command_pid" 2>/dev/null; do
  app_pid=$(pgrep -n -x "$app_name" 2>/dev/null || true)
  if [[ -n $app_pid ]]; then
    process=$(ps -o comm= -p "$app_pid" 2>/dev/null)
    rss_kib=$(ps -o rss= -p "$app_pid" 2>/dev/null | tr -d ' ')
    if [[ ${process:t} == $app_name && $rss_kib == <-> ]]; then
      (( sample_number++ ))
      print "$sample_number\t$app_pid\t$process\t$rss_kib" >> "$samples"
    fi
  fi
  sleep 0.05
done

if wait "$command_pid"; then
  command_status=0
else
  command_status=$?
fi

if (( sample_number == 0 )); then
  print -u2 "no app RSS samples captured; check executable name: $app_name"
  exit 65
fi

awk 'NR > 1 && $4 > peak { peak = $4 } END { printf "%.0f\n", peak }' \
  "$samples" > "$output_dir/peak-rss-kib.txt"
print "peak RSS: $(cat "$output_dir/peak-rss-kib.txt") KiB ($sample_number samples)"
exit "$command_status"
