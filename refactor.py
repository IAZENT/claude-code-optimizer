import os
import re
import sys

with open("claude-optimize.sh", "r") as f:
    content = f.read()

dirs = [
    "lib/core", "lib/setup", "lib/packs",
    "templates/global", "templates/project",
    "tests"
]
for d in dirs:
    os.makedirs(d, exist_ok=True)

project_start = content.find("setup_project()")
if project_start == -1:
    print("Could not find setup_project()")
    sys.exit(1)

pattern = re.compile(r'^[ \t]*smart_write\s+"([^"]+)"(.*?)\s*<<\s*\'?EOF\'?\s*?\n(.*?)^[ \t]*EOF\b', re.MULTILINE | re.DOTALL)

def replacer(match):
    dest_var = match.group(1)
    args = match.group(2)
    body = match.group(3)
    pos = match.start()
    
    is_global = pos < project_start
    layer = "global" if is_global else "project"
    
    clean_dest = dest_var.replace('"$BASE"/', '').replace('"$BASE"', '').replace('$BASE/', '').replace('$BASE', '')
    if clean_dest.startswith('/'): clean_dest = clean_dest[1:]
    if not clean_dest: clean_dest = "unnamed"
    
    # We must preserve the exact file name and directory structure inside templates/<layer>/
    template_path = f"templates/{layer}/{clean_dest}"
    
    os.makedirs(os.path.dirname(template_path), exist_ok=True)
    with open(template_path, "w") as f:
        f.write(body)
        
    # Replace in script
    # The prompt says: call `write_template "templates/global/<path>" "$DEST" [merge-flag]`
    # $DEST is dest_var here. [merge-flag] is args.
    
    # Get exact indentation
    indent = ""
    original_line = match.group(0).split('\n')[0]
    m_indent = re.match(r'^([ \t]+)', original_line)
    if m_indent:
        indent = m_indent.group(1)
        
    return f'{indent}write_template "{template_path}" "{dest_var}"{args}'

new_content = pattern.sub(replacer, content)

# Now write out the modified monolithic script so we can further split it manually.
with open("claude-optimize.sh.mod", "w") as f:
    f.write(new_content)

print("Extracted templates!")
