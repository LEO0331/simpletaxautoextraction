"""Read-only Pages landing/asset check. Never signs in or calls Firebase."""
import argparse
import re
import urllib.parse
import urllib.request


def verify(url):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != "leo0331.github.io":
        raise ValueError("Only the configured public GitHub Pages host is allowed")
    if parsed.path != "/simpletaxautoextraction/" or parsed.query or parsed.fragment:
        raise ValueError("The release must preserve its GitHub Pages base path")
    request = urllib.request.Request(url, headers={"User-Agent": "TaxWorkspaceReleaseSmoke/1.0"})
    with urllib.request.urlopen(request, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError("Landing page did not return HTTP 200")
        html = response.read().decode("utf-8")
    if not re.search(r'<base\s+href=[\"\']/simpletaxautoextraction/[\"\']\s*/?>', html):
        raise RuntimeError("Incorrect Flutter web base path")
    if "flutter_bootstrap.js" not in html:
        raise RuntimeError("Flutter bootstrap script missing")
    for asset in ("flutter_bootstrap.js", "main.dart.js"):
        request = urllib.request.Request(urllib.parse.urljoin(url, asset), method="HEAD")
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"Missing public build asset: {asset}")
    print("Public Pages landing, base path and Flutter assets passed (read-only).")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default="https://leo0331.github.io/simpletaxautoextraction/")
    verify(parser.parse_args().url)
