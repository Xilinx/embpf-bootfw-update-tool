# bdi_guard.sh
# Guard DDR work areas against U-Boot reserved ranges printed by "bdi"/"bdinfo".
# Requires: send_to_jtaguart(), COPROC[0] (active nc coprocess to the JTAG UART).

# --- Utilities ---------------------------------------------------------------

hex2dec() {
  local v="$1"
  if [[ "$v" =~ ^0x[0-9a-fA-F]+$ ]]; then
    printf '%d' "$v"
  else
    printf '%d' "$v"
  fi
}

range_end() {
  local start_dec="$1" size_dec="$2"
  if [[ "$size_dec" -eq 0 ]]; then echo "$start_dec"; else echo $(( start_dec + size_dec - 1 )); fi
}

ranges_overlap() {
  local a_start="$1" a_end="$2" b_start="$3" b_end="$4"
  if (( a_start <= b_end && b_start <= a_end )); then echo 1; else echo 0; fi
}

read_until_prompt() {
  local timeout="${1:-4}"
  local deadline=$(( SECONDS + timeout ))
  local line out=""
  while :; do
    if IFS= read -r -t 0.3 line <&"${COPROC[0]}"; then
      out+="$line"$'\n'
      [[ "$line" =~ ^\=\>\  ]] && break
    else
      (( SECONDS >= deadline )) && break
    fi
  done
  printf '%s' "$out"
}

get_reserved_ranges() {
  RESERVED_STARTS=()
  RESERVED_ENDS=()

  send_to_jtaguart " "
  sleep 1

  send_to_jtaguart "bdi"
  local dump
  dump="$(read_until_prompt 5)"

  if $verbose; then
      echo "bdi output:"
      echo "==========="
      echo "$dump"
      echo "==========="
  fi


  if ! grep -q "reserved\[" <<<"$dump"; then
    send_to_jtaguart "bdinfo"
    dump="$(read_until_prompt 5)"
  fi

  while IFS= read -r L; do
    if [[ "$L" =~ reserved\[[0-9]+\][[:space:]]*\[(0x[0-9a-fA-F]+)-(0x[0-9a-fA-F]+)\] ]]; then
      local hs="${BASH_REMATCH[1]}"
      local he="${BASH_REMATCH[2]}"
      RESERVED_STARTS+=("$(hex2dec "$hs")")
      RESERVED_ENDS+=("$(hex2dec "$he")")
    fi
  done <<< "$dump"

  ((${#RESERVED_STARTS[@]} > 0)) || {
    echo "Warning: could not find any 'reserved[...]' ranges in bdinfo output." >&2
  }
  return 0
}

check_one_candidate_against_reserved() {
  local name="$1" start_hex="$2" size_hex="$3"
  local start_dec size_dec end_dec
  start_dec="$(hex2dec "$start_hex")"
  size_dec="$(hex2dec "$size_hex")"
  end_dec="$(range_end "$start_dec" "$size_dec")"

  for ((i=0; i<${#RESERVED_STARTS[@]}; ++i)); do
    local rs="${RESERVED_STARTS[$i]}"
    local re="${RESERVED_ENDS[$i]}"
    if $verbose; then
	printf 'Checking from 0x%x - 0x%x against 0x%x - 0x%x\n' \
            "$rs" "$re" "$start_dec" "$end_dec"
    fi

    if [[ "$(ranges_overlap "$start_dec" "$end_dec" "$rs" "$re")" -eq 1 ]]; then
      printf 'Error: %s [%s - 0x%X] overlaps reserved[%d] [0x%x - 0x%x]\n' \
        "$name" "$start_hex" "$end_dec" "$i" "$rs" "$re" >&2
      return 1
    fi
  done
  return 0
}

check_pairwise_buffer_overlap() {
  local n1="$1" s1="$2" z1="$3" n2="$4" s2="$5" z2="$6"
  local d1 d2 e1 e2
  d1="$(hex2dec "$s1")"; d2="$(hex2dec "$s2")"
  e1="$(range_end "$d1" "$(hex2dec "$z1")")"
  e2="$(range_end "$d2" "$(hex2dec "$z2")")"
  echo "checking: $n1 $s1 $z1 $n2 $s2 $z2"

  if [[ "$(ranges_overlap "$d1" "$e1" "$d2" "$e2")" -eq 1 ]]; then
    printf 'Error: %s [%s - 0x%X] overlaps %s [%s - 0x%X]\n' \
      "$n1" "$s1" "$e1" "$n2" "$s2" "$e2" >&2
    return 1
  fi
  return 0
}

# --- Public API --------------------------------------------------------------
# bdi_guard_check \
#   <format> <path_to_boot_bin> \
#   <zipfile_ddr_addr> <binfile_ddr_addr> <unzipped_binfile_ddr_addr> <verify_ddr_addr> \
#   <bin_size_hex> <flash_size_hex>
#
# Returns 0 if safe, 1 if overlap detected.
bdi_guard_check() {
  local DOWNLOAD_ADDR="$1" UNZIP_ADDR="$2" VERIFY_ADDR="$3"
  local FLASH_SZ_HEX="$4"
  
  get_reserved_ranges
  

  check_one_candidate_against_reserved "download_ddr" "$DOWNLOAD_ADDR" "$FLASH_SZ_HEX" || return 1
  check_one_candidate_against_reserved "verify_ddr(bin_size)"  "$VERIFY_ADDR" "$FLASH_SZ_HEX"   || return 1
  check_one_candidate_against_reserved "unzipped_binfile_ddr" "$UNZIP_ADDR" "$FLASH_SZ_HEX" || return 1



  return 0
}
