self_install() {
  section "Installing as global command"

  local SHARE_DIR="$HOME/.local/share/claude-optimize"
  
  if [[ "$(realpath "$SCRIPT_PATH")" == "$(realpath "$INSTALL_DIR/$INSTALL_NAME")" ]]; then
    log "Already running as global command."
    return
  fi

  mkdir -p "$INSTALL_DIR"
  mkdir -p "$SHARE_DIR"
  
  # Copy everything (script, lib/, templates/)
  cp -r "$SCRIPT_DIR/"* "$SHARE_DIR/"
  chmod +x "$SHARE_DIR/claude-optimize.sh"
  
  # Symlink to bin
  ln -sf "$SHARE_DIR/claude-optimize.sh" "$INSTALL_DIR/$INSTALL_NAME"
  log "Installed → $INSTALL_DIR/$INSTALL_NAME"
  log "Resources → $SHARE_DIR/"

  local updated=false
  for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [[ -f "$rc" ]] && ! grep -q "$INSTALL_DIR" "$rc" 2>/dev/null; then
      printf '\n# claude-optimize\nexport PATH="%s:$PATH"\n' "$INSTALL_DIR" >> "$rc"
      log "Added $INSTALL_DIR to PATH in $rc"
      updated=true
    fi
  done

  blank
  echo -e "  ${BOLD}${GREEN}Installed!${RESET}  Run this to activate in your current shell:"
  blank
  bullet "source ~/.bashrc    (bash)"
  bullet "source ~/.zshrc     (zsh)"
  blank
  echo -e "  Then from any directory:"
  bullet "claude-optimize --both     # full first-time setup"
  bullet "claude-optimize --status   # check what's configured"
  blank
  exit 0
}
