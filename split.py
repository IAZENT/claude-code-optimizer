import os
import re

with open("claude-optimize.sh.mod", "r") as f:
    lines = f.readlines()

def get_function_lines(func_names):
    # Extracts the full text of multiple functions
    # by matching `func_name() {` until the closing `}` at column 0
    extracted = []
    in_func = False
    brace_level = 0
    
    # We iterate over all lines
    for line in lines:
        if not in_func:
            for fn in func_names:
                # regex to match function start
                if re.match(rf'^{fn}\(\)\s*{{', line):
                    in_func = True
                    extracted.append(line)
                    brace_level = line.count('{') - line.count('}')
                    break
        else:
            extracted.append(line)
            brace_level += line.count('{') - line.count('}')
            # We assume functions end with `}` at the start of the line or brace level reaches 0
            if brace_level == 0 and line.startswith('}'):
                in_func = False
    return "".join(extracted)

colors = ["log", "info", "warn", "error", "skip", "bullet", "dim", "blank", "doing", "dry_run_note", "divider", "section", "step_banner", "banner"]
io = ["smart_write", "_do_backup_write", "_do_merge_json", "_do_merge_md", "_ask_conflict", "make_exec"]
prompts = ["want_component", "ask_yn", "select_mode"] # add ask_choice later
deps = ["check_deps"]
status = ["show_status"]
global_sh = ["setup_global"]
project_sh = ["setup_project"]
self_install = ["self_install"]

# We need to create the write_template function and append it to io.sh
write_template = """
write_template() {
  local template_path="$1"
  local dest_path="$2"
  shift 2
  cat "$SCRIPT_DIR/$template_path" | smart_write "$dest_path" "$@"
}
"""

with open("lib/core/colors.sh", "w") as f: f.write(get_function_lines(colors))
with open("lib/core/io.sh", "w") as f: f.write(get_function_lines(io) + write_template)
with open("lib/core/prompts.sh", "w") as f: f.write(get_function_lines(prompts))
with open("lib/core/deps.sh", "w") as f: f.write(get_function_lines(deps))
with open("lib/core/status.sh", "w") as f: f.write(get_function_lines(status))
with open("lib/setup/global.sh", "w") as f: f.write(get_function_lines(global_sh))
with open("lib/setup/project.sh", "w") as f: f.write(get_function_lines(project_sh))
with open("lib/self_install.sh", "w") as f: f.write(get_function_lines(self_install))

# Now build the thin entrypoint
# We need the header (colors, flags, tracking) and the main script logic.
# The easiest way is to extract the preamble and main() logic, or just write it.
header_lines = []
for line in lines:
    if line.startswith("log()"): 
        break
    header_lines.append(line)

main_functions = ["install_tools", "print_manual_steps", "print_project_checklist", "print_final_summary", "do_analyze", "do_set_budget", "do_upgrade", "main", "preflight_scan"]
main_code = get_function_lines(main_functions)

thin_script = "".join(header_lines) + """
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

for f in "$SCRIPT_DIR"/lib/core/*.sh; do source "$f"; done
for f in "$SCRIPT_DIR"/lib/setup/*.sh; do source "$f"; done
source "$SCRIPT_DIR"/lib/self_install.sh

""" + main_code + """
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
"""

with open("claude-optimize.sh", "w") as f:
    f.write(thin_script)

print("Split complete!")
