# usage: drvPathDiff [--dungeon REF] [--den REF] [--input NAME] [--ignore NAME]... [--packages] [--no-auto] [--out FILE] <flake-ref> [attr...]
# Evaluates drvPaths of <flake-ref> with its own input (Den) and with the input
# overridden by dungeon. Prints OK/DIFF/ERR. On DIFF/ERR writes a GitHub issue body.
dungeon=github:vic/dungeon input=den out= den= pk=false auto=true ignore=()
while [ $# -gt 0 ]; do
  case $1 in
    --dungeon) dungeon=$2; shift 2 ;;
    --input) input=$2; shift 2 ;;
    --out) out=$2; shift 2 ;;
    --den) den=$2; shift 2 ;;
    --ignore) ignore+=("$2"); shift 2 ;;
    --packages) pk=true; shift ;;
    --no-auto) auto=false; shift ;;
    -h|--help) sed -n '2,4p' "$0" 2>/dev/null || true; echo "usage: drvPathDiff [--dungeon REF|path:/dir] [--den REF|DIR] [--input NAME] [--ignore NAME]... [--packages] [--no-auto] [--out FILE] <flake-ref> [attr...]"; exit 0 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "usage: drvPathDiff [--dungeon REF] [--den REF|DIR] [--input NAME] [--ignore NAME]... [--packages] [--no-auto] [--out FILE] <flake-ref> [attr...]" >&2; exit 2; }
ref=$1; shift
case $ref in *'#'*) echo "give the flake ref without #; pass attrs as extra args" >&2; exit 2 ;; esac
case $dungeon in /*|./*) dungeon="path:$(realpath "$dungeon")" ;; esac
case $den in /*|./*) den="path:$(realpath "$den")" ;; esac
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
apply=$(cat "$DRVPATHS_NIX")

# side <name> [override-args...] -> $tmp/<name>.txt, lines "<attr> <drv|ERR>", $tmp/<name>.err
side() {
  name=$1; shift
  : > "$tmp/$name.txt"; : > "$tmp/$name.err"
  if ! $auto; then :
  elif raw=$(nix eval --no-write-lock-file "$@" --raw "$ref#." --apply "($apply) $pk" 2>"$tmp/$name.err"); then
    printf '%s\n' "$raw" | sed '/^$/d' > "$tmp/$name.txt"
  else
    echo "<flake> ERR" > "$tmp/$name.txt"; cat "$tmp/$name.err" >&2
  fi
  for a in "${attrs[@]}"; do
    case $a in
      nixosConfigurations.*|darwinConfigurations.*) sel=.config.system.build.toplevel ;;
      homeConfigurations.*) sel=.activationPackage ;;
      *) sel= ;;
    esac
    if d=$(nix eval --no-write-lock-file "${ovr[@]}" --raw "$ref#$a$sel.drvPath" 2>>"$tmp/$name.err"); then
      echo "${a##*.} $d" >> "$tmp/$name.txt"
    elif [ "${a%%.*}" = nixosConfigurations ] && d=$(nix eval --no-write-lock-file "${ovr[@]}" --raw "$ref#$a.config.system.build.etc.drvPath" 2>>"$tmp/$name.err"); then
      echo "${a##*.} etc:$d" >> "$tmp/$name.txt"   # toplevel throws (also on Den): compare etc
    else echo "${a##*.} ERR" >> "$tmp/$name.txt"; fi
  done
}
attrs=("$@")
ovr=()
[ -z "$den" ] || ovr=(--override-input "$input" "$den")
side den "${ovr[@]}"
ovr=(--override-input "$input" "$dungeon")
side dungeon "${ovr[@]}"

declare -A D G
for n in "${ignore[@]}"; do sed -i "/^$n /d" "$tmp/den.txt" "$tmp/dungeon.txt"; done
while read -r k v; do D[$k]=$v; done < "$tmp/den.txt"
while read -r k v; do G[$k]=$v; done < "$tmp/dungeon.txt"
[ $((${#D[@]} + ${#G[@]})) -gt 0 ] || { echo "ERR    nothing to compare" >&2; exit 1; }
bad=()
printf '%-6s %s\n' STATUS ATTR
for k in $(printf '%s\n' "${!D[@]}" "${!G[@]}" | sort -u); do
  d=${D[$k]:-missing} g=${G[$k]:-missing}
  if [ "$g" = ERR ] || [ "$g" = missing ]; then s=ERR
  elif [ "$d" = ERR ]; then s=ERR
  elif [ "$d" = "$g" ]; then s=OK
  else s=DIFF; fi
  printf '%-6s %s\n' "$s" "$k"
  [ "$s" = OK ] || bad+=("$k")
done
[ ${#bad[@]} -eq 0 ] && exit 0

rev() { nix flake metadata --json "$1" 2>/dev/null | jq -r '.locked.rev // .revision // .locked.narHash // "unknown"' 2>/dev/null || echo unknown; }
denrev=$(nix flake metadata --json "$ref" 2>/dev/null | jq -r --arg i "$input" '.locks.nodes[$i].locked | (.rev // .narHash // "unknown")' 2>/dev/null || echo unknown)
[ -n "$out" ] || out=$(mktemp --suffix=.md)
{
  echo "## drvPath differs from Den"
  echo
  echo "- flake: \`$ref\`"
  echo "- den input \`$input\` rev: \`$denrev\`"
  echo "- dungeon: \`$dungeon\` rev: \`$(rev "$dungeon")\`"
  echo "- nix: \`$(nix --version)\`"
  echo
  echo "### Failing attrs"
  echo
  echo "| attr | Den | dungeon |"
  echo "|---|---|---|"
  for k in "${bad[@]}"; do echo "| \`$k\` | \`${D[$k]:-missing}\` | \`${G[$k]:-missing}\` |"; done
  echo
  echo "### First error line"
  echo
  for n in den dungeon; do
    echo "- $n: \`$(sed 's/\x1b\[[0-9;]*m//g' "$tmp/$n.err" | grep -E 'error:.*[^ ]' | tail -1 | cut -c1-300 || true)\`"
  done
} > "$out"
echo
echo "issue body: $out"
echo "gh issue create -R vic/dungeon --title 'drvPath diff: $ref' --body-file $out"
exit 1
