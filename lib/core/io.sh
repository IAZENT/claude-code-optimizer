smart_write() {
  local dest="$1"; shift
  local mode_flag="${1:-}"
  local content
  content=$(cat)

  local short_dest="${dest/#$HOME/~}"

  if $DRY_RUN; then
    echo -e "  ${MAGENTA}[DRY-RUN]${RESET}  Would write: ${BOLD}$short_dest${RESET}"
    TRACK_CREATED+=("$short_dest  [dry-run]")
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  # ── New file ──────────────────────────────────────────────────────────────
  if [[ ! -e "$dest" ]]; then
    echo "$content" > "$dest"
    local sz
    sz=$(wc -c < "$dest" | tr -d ' ')
    log "Created  ${BOLD}$short_dest${RESET}  ${DIM}(${sz}b)${RESET}"
    TRACK_CREATED+=("$short_dest")
    return 0
  fi

  # ── File exists, content identical ────────────────────────────────────────
  if [[ "$(cat "$dest")" == "$content" ]]; then
    skip "$short_dest  (identical — nothing to do)"
    TRACK_SKIPPED+=("$short_dest  [identical]")
    return 0
  fi

  # ── Forced flags ──────────────────────────────────────────────────────────
  case "$mode_flag" in
    --force)      _do_backup_write "$dest" "$content" "$short_dest"; return 0 ;;
    --safe)       skip "$short_dest  (kept your version)"; TRACK_SKIPPED+=("$short_dest  [kept]"); return 0 ;;
    --merge-json) _do_merge_json   "$dest" "$content" "$short_dest"; return 0 ;;
    --merge-md)   _do_merge_md     "$dest" "$content" "$short_dest"; return 0 ;;
  esac

  # ── No flag — follow CONFLICT_POLICY ─────────────────────────────────────
  case "$CONFLICT_POLICY" in
    safe)   skip "$short_dest  (kept your version)"; TRACK_SKIPPED+=("$short_dest  [kept]") ;;
    force)  _do_backup_write "$dest" "$content" "$short_dest" ;;
    ask|*)  _ask_conflict "$dest" "$content" "$short_dest" ;;
  esac
}
_do_backup_write() {
  local dest="$1" content="$2" short="$3"
  local bak="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$dest" "$bak"
  echo "$content" > "$dest"
  local sz; sz=$(wc -c < "$dest" | tr -d ' ')
  warn "Backed up  ${DIM}$(basename "$bak")${RESET}"
  log  "Updated   ${BOLD}$short${RESET}  ${DIM}(${sz}b)${RESET}"
  TRACK_MODIFIED+=("$short")
  TRACK_BACKUPS+=("$(basename "$bak") → $bak")
}
_do_merge_json() {
  local dest="$1" content="$2" short="$3"
  if ! $JQ_AVAILABLE; then
    warn "jq not found — cannot merge $short"
    info "Keeping your version. Merge manually if needed."
    TRACK_SKIPPED+=("$short  [jq missing — kept]")
    return
  fi
  local merged
  merged=$(jq -s '
    def merge_perms(a; b):
      { allow: ([a.allow//[], b.allow//[]] | flatten | unique),
        deny:  ([a.deny//[],  b.deny//[]]  | flatten | unique) };
    .[0] as $old | .[1] as $new |
    $new + $old +
    (if ($old.permissions and $new.permissions)
     then { permissions: merge_perms($old.permissions; $new.permissions) }
     else {} end) +
    (if ($old.mcpServers and $new.mcpServers)
     then { mcpServers: ($new.mcpServers + $old.mcpServers) }
     else {} end)
  ' "$dest" <(echo "$content") 2>/dev/null) || {
    warn "JSON merge failed for $short — keeping your version."
    TRACK_SKIPPED+=("$short  [merge failed — kept]")
    return
  }
  local bak="${dest}.bak.$(date +%Y%m%d-%H%M%S)"
  cp "$dest" "$bak"
  echo "$merged" > "$dest"
  warn "Backed up  ${DIM}$(basename "$bak")${RESET}"
  log  "Merged    ${BOLD}$short${RESET}  ${DIM}(your settings preserved, new keys added)${RESET}"
  TRACK_MODIFIED+=("$short  [merged]")
  TRACK_BACKUPS+=("$(basename "$bak") → $bak")
}
_do_merge_md() {
  local dest="$1" content="$2" short="$3"
  local added=0
  local in_block=false block_name="" block_lines=()

  while IFS= read -r line; do
    if [[ "$line" =~ ^##\  ]]; then
      if [[ -n "$block_name" && $added -eq 0 || -n "$block_name" ]]; then
        if ! grep -qF "$block_name" "$dest" 2>/dev/null; then
          { echo ""; echo "---"; echo "<!-- Added by claude-optimize -->"; echo "$block_name"; printf '%s\n' "${block_lines[@]}"; } >> "$dest"
          ((added++)) || true
        fi
      fi
      block_name="$line"; block_lines=()
    elif [[ -n "$block_name" ]]; then
      block_lines+=("$line")
    fi
  done <<< "$content"

  # flush last block
  if [[ -n "$block_name" ]] && ! grep -qF "$block_name" "$dest" 2>/dev/null; then
    { echo ""; echo "---"; echo "$block_name"; printf '%s\n' "${block_lines[@]}"; } >> "$dest"
    ((added++)) || true
  fi

  if [[ $added -gt 0 ]]; then
    log "Merged  ${BOLD}$short${RESET}  ${DIM}($added new section(s) added)${RESET}"
    TRACK_MODIFIED+=("$short  [+${added} sections]")
  else
    skip "$short  (all sections already present)"
    TRACK_SKIPPED+=("$short  [all sections present]")
  fi
}
_ask_conflict() {
  local dest="$1" content="$2" short="$3"
  blank
  warn "File exists with different content: ${BOLD}$short${RESET}"
  dim  "Existing: $(wc -c < "$dest" | tr -d ' ')b  |  New template: ${#content}b"
  blank
  echo -e "  ${CYAN}[K]${RESET}  Keep yours    — skip, keep your current file"
  echo -e "  ${CYAN}[O]${RESET}  Overwrite     — backup yours → .bak.TIMESTAMP, write new"
  echo -e "  ${CYAN}[D]${RESET}  Show diff     — see what's different, then choose again"
  [[ "$dest" == *.json ]] && echo -e "  ${CYAN}[M]${RESET}  Merge JSON    — combine both (your keys + new keys)"
  [[ "$dest" == *.md   ]] && echo -e "  ${CYAN}[M]${RESET}  Merge MD      — append only missing ## sections"
  blank
  local choice
  printf "  ${CYAN}▶${RESET} ${BOLD}Choose [K/o/d/m]:${RESET} "
  read -r choice
  choice="${choice:-K}"

  case "${choice^^}" in
    K)  skip "$short  (kept your version)"; TRACK_SKIPPED+=("$short  [kept]") ;;
    O)  _do_backup_write "$dest" "$content" "$short" ;;
    D)
      blank
      diff --color=always -u "$dest" <(echo "$content") 2>/dev/null \
        || diff -u "$dest" <(echo "$content") 2>/dev/null \
        || echo "(diff unavailable)"
      blank
      _ask_conflict "$dest" "$content" "$short"   # recursive — ask again after diff
      ;;
    M)
      if   [[ "$dest" == *.json ]]; then _do_merge_json "$dest" "$content" "$short"
      elif [[ "$dest" == *.md   ]]; then _do_merge_md   "$dest" "$content" "$short"
      else warn "Merge not supported for this file type."; TRACK_SKIPPED+=("$short  [kept]"); fi
      ;;
    *)  warn "Invalid input '$choice'. Keeping your version."; TRACK_SKIPPED+=("$short  [kept]") ;;
  esac
}
make_exec() {
  $DRY_RUN && return
  chmod +x "$1"
  local short="${1/#$HOME/~}"
  dim "chmod +x $short"
}

write_template() {
  local template_path="$1"
  local dest_path="$2"
  shift 2
  cat "$SCRIPT_DIR/$template_path" | smart_write "$dest_path" "$@"
}
