#!/usr/bin/env python3
"""Check the standalone GitHub Pages artifact without network or dependencies."""
from html.parser import HTMLParser
from pathlib import Path
from tempfile import TemporaryDirectory
from urllib.parse import unquote, urlsplit
import re
import sys


class Page(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.ids, self.refs, self.h1s = set(), [], 0
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            if attrs["id"] in self.ids:
                raise ValueError(f"Duplicate ID: {attrs['id']}")
            self.ids.add(attrs["id"])
        self.h1s += tag == "h1"
        if tag == "img" and "alt" not in attrs:
            raise ValueError("Image missing alt text")
        for key in ("src", "href"):
            if attrs.get(key):
                self.refs.append(attrs[key])
        if attrs.get("srcset"):
            self.refs.extend(item.strip().split()[0] for item in attrs["srcset"].split(",") if item.strip())


def check_site(site):
    site = site.resolve()
    if not (site / "index.html").is_file():
        raise ValueError("Missing site/index.html")
    if not (site / "CNAME").is_file() or (site / "CNAME").read_text().strip() != "cuckoding.com":
        raise ValueError("CNAME must be cuckoding.com")
    if not (site / ".nojekyll").is_file():
        raise ValueError("Missing .nojekyll")
    files = list(site.rglob("*"))
    if any(path.is_symlink() for path in files):
        raise ValueError("Pages assets must not be symlinks")
    pages = {path: Page(path.read_text()) for path in files if path.suffix == ".html"}
    if pages[site / "index.html"].h1s != 1:
        raise ValueError("index.html must have exactly one h1")

    def check_ref(source, ref):
        url = urlsplit(ref)
        if url.scheme or url.netloc:
            if url.scheme not in ("https", "mailto", "tel", "data"):
                raise ValueError(f"Unsupported URL: {ref}")
            return
        relative = unquote(url.path)
        if relative.startswith("/"):
            raise ValueError(f"Use project-path-safe asset/link: {ref}")
        target = (source.parent / relative).resolve() if relative else source
        if target.is_dir():
            target /= "index.html"
        if not target.is_relative_to(site) or not target.is_file():
            raise ValueError(f"Missing or outside asset/link in {source.name}: {ref}")
        if url.fragment and target.suffix == ".html":
            if unquote(url.fragment) not in pages[target].ids:
                raise ValueError(f"Missing fragment in {source.name}: {ref}")

    count = 0
    for path, page in pages.items():
        for ref in page.refs:
            check_ref(path, ref)
            count += 1
    for path in files:
        if path.suffix == ".css":
            css = re.sub(r"/\*.*?\*/", "", path.read_text(), flags=re.S)
            for match in re.finditer(r"url\(\s*(['\"]?)(.*?)\1\s*\)", css, re.S):
                check_ref(path, match[2].strip())
                count += 1
    return count


def self_test():
    with TemporaryDirectory(prefix="cuckoding-site-check-") as scratch:
        site = Path(scratch)
        page = '<h1 id="top">Hello</h1><a href="#top">Top</a><img alt="" src="art.svg" srcset="art.svg 1x, art.svg 2x"><link href="style.css">'
        (site / "index.html").write_text(page)
        (site / "art.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg"/>')
        (site / "style.css").write_text('body { background: url("art.svg"); }')
        (site / "CNAME").write_text("cuckoding.com\n")
        (site / ".nojekyll").touch()
        check_site(site)
        cases = [
            ("index.html", page.replace("#top", "#missing")),
            ("index.html", page.replace('src="art.svg"', 'src="missing.svg"')),
            ("index.html", page.replace("art.svg 2x", "missing.svg 2x")),
            ("index.html", page.replace('src="art.svg"', 'src="/art.svg"')),
            ("index.html", page.replace(' alt=""', "")),
            ("index.html", page + '<h1>Second</h1>'),
            ("index.html", page + '<p id="top">Duplicate</p>'),
            ("style.css", 'body { background: url(missing.svg); }'),
            ("CNAME", "wrong.example"),
        ]
        for name, malformed in cases:
            path = site / name
            original = path.read_text()
            path.write_text(malformed)
            try:
                check_site(site)
            except ValueError:
                pass
            else:
                raise AssertionError(f"Checker accepted malformed {name}: {malformed}")
            finally:
                path.write_text(original)
        (site / ".nojekyll").unlink()
        try:
            check_site(site)
        except ValueError:
            pass
        else:
            raise AssertionError("Checker accepted missing .nojekyll")
    print("PASS: valid fixture and 10 malformed static-site fixtures")


if __name__ == "__main__":
    try:
        if sys.argv[1:] == ["--self-test"]:
            self_test()
        elif not sys.argv[1:]:
            count = check_site(Path(__file__).resolve().parents[1] / "site")
            print(f"PASS: {count} links/assets, image alternatives, headings and Pages files")
        else:
            raise ValueError("Usage: python3 scripts/check_site.py [--self-test]")
    except (ValueError, OSError) as error:
        sys.exit(f"FAIL: {error}")
