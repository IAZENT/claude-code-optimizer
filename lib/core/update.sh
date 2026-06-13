do_update() {
  section "Self-Update"
  
  local SHARE_DIR="$HOME/.local/share/claude-optimize"
  local REPO_URL="https://github.com/IAZENT/claude-code-optimizer.git"
  local TMP_DIR="/tmp/claude-optimize-update"

  if [[ ! -d "$SHARE_DIR" ]]; then
    error "Not installed via bash installer."
    info "If you installed via PyPI, run: pip install --upgrade claudeoptimize"
    exit 1
  fi

  log "Downloading latest version from $REPO_URL..."
  
  rm -rf "$TMP_DIR"
  if git clone --depth 1 "$REPO_URL" "$TMP_DIR" &>/dev/null; then
    log "Download complete. Installing..."
    cp -r "$TMP_DIR/"* "$SHARE_DIR/"
    chmod +x "$SHARE_DIR/claude-optimize.sh"
    rm -rf "$TMP_DIR"
    
    echo -e "  ${GREEN}✔ Update successful!${RESET} You are running the latest version."
  else
    error "Failed to download update. Check your internet connection or git installation."
    exit 1
  fi
}
