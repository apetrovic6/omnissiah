#!/usr/bin/env bash
#
# Ask the old resolver (Technitium) and the new ones (Blocky) the same
# questions and report where they disagree, before any client is switched over.
#
# The LAN resolver is moving from Technitium (cerberus, 192.168.1.105:53) to
# three Blocky instances (cerberus .105, ryza .45, servitor .13), first running
# in parallel on port 5335. Each candidate is compared against the reference
# for four name sets:
#
#   1. split-horizon  sorted A-record sets must be IDENTICAL
#      (plus an informational set -- the apex names -- that is reported but
#      never fails: Technitium has no apex record, Blocky maps it)
#   2. blocked        must be blocked on the candidate AND the reference.
#                     "Blocked" = NXDOMAIN, or only 0.0.0.0 / :: answers
#   3. public         both must return at least one A record; the addresses
#                     are NOT compared (CDN answers differ per server)
#   4. per-machine    <host>.omnissiah.internal must return the machine's LAN
#                     IP on every candidate. The reference is not asked
#                     (Technitium does not serve these); a candidate that IS
#                     the reference is skipped.
#
# A server that does not answer at all (timeout) is "unreachable": reported
# once per server, counted separately, and never a mismatch -- but it does keep
# the exit code from being green (exit 3), since nothing was actually compared.
#
# Usage:  ./rituals/dns-compare.sh [--reference HOST[:PORT]] [CANDIDATE[:PORT] ...]
#   reference   default 192.168.1.105:53
#   candidates  default 192.168.1.105:5335 192.168.1.45:5335 192.168.1.13:5335
#   (port defaults to 53)
#
# Needs `dig`:  nix shell nixpkgs#dig -c ./rituals/dns-compare.sh
#
# Exit: 0 everything checked and matched
#       1 at least one mismatch in sets 1-4 (wins over 3)
#       2 usage error
#       3 no mismatches, but at least one server (candidate or reference) was unreachable
# Read-only: it only sends DNS queries.

set -euo pipefail

DEFAULT_REFERENCE="192.168.1.105:53"
DEFAULT_CANDIDATES=("192.168.1.105:5335" "192.168.1.45:5335" "192.168.1.13:5335")

# --- Name sets ---------------------------------------------------------------

# Set 1: split-horizon names, A record sets must match exactly.
SPLIT_HORIZON=(
  argocd.noosphere.uk
  forge.noosphere.uk
  a.b.noosphere.uk # nested subdomain, exercises the wildcard
  x.keksic.xyz
  ugalabugala.org   # public VPS answer
  matrix.ugalabugala.org # public VPS answer
)
for _n in ha forge ntfy immich vaultwarden kaneo memos dav plex tautulli \
  audiobookshelf nopresh pilot proxmox syn technitium; do
  SPLIT_HORIZON+=("${_n}.ugalabugala.org")
done

# Set 1b: informational. Apex records may legitimately differ.
INFORMATIONAL=(noosphere.uk keksic.xyz)

# Set 2: must be blocked on both. All on StevenBlack hosts and hagezi pro.plus;
# each verified NXDOMAIN on Technitium (and resolvable on 1.1.1.1) on 2026-11-22.
BLOCKED=(doubleclick.net googleadservices.com adservice.google.com app-measurement.com)

# Set 3: must resolve on both; only the presence of an A record is checked.
PUBLIC=(example.com github.com nixos.org cache.nixos.org)

# Set 4: per-machine names -> expected IP, candidates only.
PER_MACHINE=(
  "cerberus.omnissiah.internal=192.168.1.105"
  "ryza.omnissiah.internal=192.168.1.45"
)

# --- Arguments ---------------------------------------------------------------

usage() {
  echo "usage: ${0##*/} [--reference HOST[:PORT]] [CANDIDATE[:PORT] ...]" >&2
  exit 2
}

reference="$DEFAULT_REFERENCE"
candidates=()
while (($#)); do
  case "$1" in
    --reference)
      (($# >= 2)) || usage
      reference="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    -*) usage ;;
    *)
      candidates+=("$1")
      shift
      ;;
  esac
done
((${#candidates[@]})) || candidates=("${DEFAULT_CANDIDATES[@]}")

command -v dig >/dev/null || {
  echo "dig not found; run: nix shell nixpkgs#dig -c $0" >&2
  exit 2
}

normalise() { [[ "$1" == *:* ]] && echo "$1" || echo "$1:53"; }
reference="$(normalise "$reference")"
for i in "${!candidates[@]}"; do candidates[i]="$(normalise "${candidates[i]}")"; done

# --- Querying ----------------------------------------------------------------

# query SERVER NAME -> sets QR to "TIMEOUT" or "<STATUS> <sorted A records, space separated>"
# Sets the global QR (not stdout: caches must survive, so no subshell). Cached.
# A server that times out once is not asked again (saves 2s per remaining name).
QR=""
declare -A CACHE=() DEAD=()
query() {
  local server="$1" name="$2" key="$1|$2" host port out rc=0
  if [[ -n "${DEAD[$server]+x}" ]]; then
    QR=TIMEOUT
    return
  fi
  if [[ -n "${CACHE[$key]+x}" ]]; then
    QR="${CACHE[$key]}"
    return
  fi
  host="${server%:*}"
  port="${server##*:}"
  out="$(dig +time=2 +tries=1 +noall +comments +answer -p "$port" "@$host" A "$name" 2>/dev/null)" || rc=$?
  local result status addrs
  if ((rc != 0)) || ! grep -q 'status:' <<<"$out"; then
    result="TIMEOUT"
    DEAD[$server]=1
  else
    status="$(sed -n 's/.*status: \([A-Z]*\).*/\1/p' <<<"$out" | head -1)"
    addrs="$(awk '$4 == "A" {print $5}' <<<"$out" | sort | paste -sd' ' -)"
    result="$status $addrs"
  fi
  CACHE[$key]="$result"
  QR="$result"
}

is_blocked() { # RESULT
  local status="${1%% *}" addrs="${1#* }" a
  [[ "$status" == NXDOMAIN ]] && return 0
  [[ "$status" == NOERROR ]] || return 1
  [[ "$1" == "$status" ]] && return 1 # NOERROR, no data
  for a in $addrs; do [[ "$a" == 0.0.0.0 || "$a" == :: ]] || return 1; done
  return 0
}

has_a() { # RESULT
  [[ "${1%% *}" == NOERROR && "$1" != "${1%% *}" && "${1#* }" != "" ]]
}

# --- Bookkeeping ---------------------------------------------------------------

declare -A CHECKED=() OK=() MISMATCH=() UNREACH=() UNREACH_SERVERS=()
SETS=("1 split-horizon" "1b informational" "2 blocked" "3 public" "4 per-machine")
for s in "${SETS[@]}"; do CHECKED[$s]=0 OK[$s]=0 MISMATCH[$s]=0 UNREACH[$s]=0; done

record() { # SET STATE(ok|bad|unreach) NAME SERVER DETAIL
  local set="$1" state="$2"
  CHECKED[$set]=$((CHECKED[$set] + 1))
  case "$state" in
    ok) OK[$set]=$((OK[$set] + 1)) ;;
    bad)
      MISMATCH[$set]=$((MISMATCH[$set] + 1))
      echo "MISMATCH [$set] $3 @ $4: $5"
      ;;
    info)
      MISMATCH[$set]=$((MISMATCH[$set] + 1))
      echo "INFO     [$set] $3 @ $4: $5"
      ;;
    unreach)
      UNREACH[$set]=$((UNREACH[$set] + 1))
      UNREACH_SERVERS[$4]=1
      ;;
  esac
}

show() { [[ "$1" == TIMEOUT ]] && echo "timeout" || echo "${1%% *} [${1#* }]"; }

# compare_exact SET NAME CAND: reference and candidate A sets must be identical.
compare_exact() {
  local set="$1" name="$2" cand="$3" ref got bad=bad
  [[ "$set" == "1b informational" ]] && bad=info
  query "$reference" "$name"; ref=$QR
  query "$cand" "$name"; got=$QR
  if [[ "$got" == TIMEOUT ]]; then
    record "$set" unreach "$name" "$cand"
  elif [[ "$ref" == TIMEOUT ]]; then
    record "$set" unreach "$name" "$reference"
  elif [[ "$ref" == "$got" ]]; then
    record "$set" ok "$name" "$cand"
  else
    record "$set" "$bad" "$name" "$cand" "got $(show "$got"), reference $(show "$ref")"
  fi
}

# --- Run -----------------------------------------------------------------------

echo "reference: $reference"
echo "candidates: ${candidates[*]}"
echo

for cand in "${candidates[@]}"; do
  for name in "${SPLIT_HORIZON[@]}"; do compare_exact "1 split-horizon" "$name" "$cand"; done
  for name in "${INFORMATIONAL[@]}"; do compare_exact "1b informational" "$name" "$cand"; done

  for name in "${BLOCKED[@]}"; do
    query "$reference" "$name"; ref=$QR
    query "$cand" "$name"; got=$QR
    if [[ "$got" == TIMEOUT ]]; then
      record "2 blocked" unreach "$name" "$cand"
    elif [[ "$ref" == TIMEOUT ]]; then
      record "2 blocked" unreach "$name" "$reference"
    elif ! is_blocked "$got"; then
      record "2 blocked" bad "$name" "$cand" "not blocked: $(show "$got")"
    elif ! is_blocked "$ref"; then
      record "2 blocked" bad "$name" "$reference" "reference does not block it: $(show "$ref")"
    else
      record "2 blocked" ok "$name" "$cand"
    fi
  done

  for name in "${PUBLIC[@]}"; do
    query "$reference" "$name"; ref=$QR
    query "$cand" "$name"; got=$QR
    if [[ "$got" == TIMEOUT ]]; then
      record "3 public" unreach "$name" "$cand"
    elif [[ "$ref" == TIMEOUT ]]; then
      record "3 public" unreach "$name" "$reference"
    elif ! has_a "$got"; then
      record "3 public" bad "$name" "$cand" "no A record: $(show "$got")"
    elif ! has_a "$ref"; then
      record "3 public" bad "$name" "$reference" "reference has no A record: $(show "$ref")"
    else
      record "3 public" ok "$name" "$cand"
    fi
  done

  if [[ "$cand" == "$reference" ]]; then
    echo "skip     [4 per-machine] $cand is the reference (does not serve these names)"
  else
    for entry in "${PER_MACHINE[@]}"; do
      name="${entry%%=*}"
      want="${entry#*=}"
      query "$cand" "$name"; got=$QR
      if [[ "$got" == TIMEOUT ]]; then
        record "4 per-machine" unreach "$name" "$cand"
      elif [[ "$got" == "NOERROR $want" ]]; then
        record "4 per-machine" ok "$name" "$cand"
      else
        record "4 per-machine" bad "$name" "$cand" "got $(show "$got"), want $want"
      fi
    done
  fi
done

# --- Summary -------------------------------------------------------------------

echo
for s in "${!UNREACH_SERVERS[@]}"; do echo "UNREACHABLE: $s (no answer)"; done
echo
printf '%-18s %8s %5s %11s %12s\n' set checked ok mismatched unreachable
total_bad=0
for s in "${SETS[@]}"; do
  printf '%-18s %8d %5d %11d %12d\n' "$s" "${CHECKED[$s]}" "${OK[$s]}" "${MISMATCH[$s]}" "${UNREACH[$s]}"
  [[ "$s" == "1b informational" ]] || total_bad=$((total_bad + MISMATCH[$s]))
done

((total_bad == 0)) || exit 1
((${#UNREACH_SERVERS[@]} == 0)) || exit 3
