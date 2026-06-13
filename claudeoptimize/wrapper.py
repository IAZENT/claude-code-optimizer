import os
import sys
import subprocess

def main():
    script_path = os.path.join(os.path.dirname(__file__), "claude-optimize.sh")
    if not os.path.exists(script_path):
        print(f"Error: Could not find {script_path}", file=sys.stderr)
        sys.exit(1)
        
    # We must ensure the script is executable
    if not os.access(script_path, os.X_OK):
        os.chmod(script_path, 0o755)
        
    sys.exit(subprocess.call(["bash", script_path] + sys.argv[1:]))

if __name__ == "__main__":
    main()
