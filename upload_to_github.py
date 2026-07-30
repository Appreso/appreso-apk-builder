import os
import sys
import base64
import json
import urllib.request

TOKEN = "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"
REPO = "Appreso/appreso-apk-builder"
BRANCH = "main"
LOCAL_DIR = "/Users/shamiulbishal/Local Sites/apk/app/public/wp-content/plugins/AppReso/appreso-apk-builder"

def api_request(method, url, data=None):
    req = urllib.request.Request(url, method=method)
    req.add_header("Authorization", f"Bearer {TOKEN}")
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data:
        req.add_header("Content-Type", "application/json")
        req.data = json.dumps(data).encode("utf-8")
    try:
        with urllib.request.urlopen(req) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"Error {e.code}: {e.read().decode('utf-8')}")
        sys.exit(1)

def main():
    print("Getting base tree...")
    ref_info = api_request("GET", f"https://api.github.com/repos/{REPO}/git/ref/heads/{BRANCH}")
    commit_sha = ref_info['object']['sha']
    commit_info = api_request("GET", f"https://api.github.com/repos/{REPO}/git/commits/{commit_sha}")
    base_tree_sha = commit_info['tree']['sha']

    tree = []
    
    # We want to replace everything, but we can't easily delete via tree API unless we provide the exact new tree.
    # Actually, we can create a completely new tree and point the commit to it.
    
    for root, dirs, files in os.walk(LOCAL_DIR):
        if '.git' in root or 'logs' in root:
            continue
        for file in files:
            if file == '.DS_Store' or file.endswith('.zip'):
                continue
                
            file_path = os.path.join(root, file)
            rel_path = os.path.relpath(file_path, LOCAL_DIR)
            
            print(f"Uploading blob: {rel_path}")
            with open(file_path, "rb") as f:
                content = base64.b64encode(f.read()).decode("utf-8")
                
            blob_info = api_request("POST", f"https://api.github.com/repos/{REPO}/git/blobs", {
                "content": content,
                "encoding": "base64"
            })
            
            tree.append({
                "path": rel_path,
                "mode": "100644",
                "type": "blob",
                "sha": blob_info['sha']
            })

    print("Creating tree...")
    new_tree_info = api_request("POST", f"https://api.github.com/repos/{REPO}/git/trees", {
        "tree": tree
    }) # No base_tree means it replaces the entire repository contents!
    
    print("Creating commit...")
    new_commit_info = api_request("POST", f"https://api.github.com/repos/{REPO}/git/commits", {
        "message": "Fix repository structure (moved files to root)",
        "tree": new_tree_info['sha'],
        "parents": [commit_sha]
    })
    
    print("Updating ref...")
    api_request("PATCH", f"https://api.github.com/repos/{REPO}/git/refs/heads/{BRANCH}", {
        "sha": new_commit_info['sha'],
        "force": True
    })
    print("Done!")

if __name__ == "__main__":
    main()
