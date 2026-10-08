#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

notes="$WORK/notes"
mkdir -p "$notes"
cat > "$notes/en.md" <<'NOTE'
# Version %VERSION% (Build %BUILD%)
- English item.
NOTE
cat > "$notes/zh-Hans.md" <<'NOTE'
# 版本 %VERSION%（构建 %BUILD%）
- 中文条目。
NOTE

cat > "$WORK/history.xml" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Status Trio</title>
    <item>
      <title xml:lang="en">Version 1.4.0 (Build 17)</title>
      <pubDate>Wed, 30 Sep 2026 15:54:38 +0000</pubDate>
      <sparkle:version>17</sparkle:version>
      <sparkle:shortVersionString>1.4.0</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <description xml:lang="en"><![CDATA[<p>old</p>]]></description>
      <enclosure url="https://example.invalid/StatusTrio-1.4.0.dmg"
                 type="application/octet-stream"
                 sparkle:edSignature="old-signature"
                 length="42" />
    </item>
  </channel>
</rss>
XML
cp "$WORK/history.xml" "$WORK/original.xml"

ruby "$ROOT/scripts/update-appcast.rb" \
    --version 1.5.0 \
    --build 18 \
    --notes-dir "$notes" \
    --appcast "$WORK/history.xml" \
    --output "$WORK/generated.xml" \
    --dmg-url "https://example.invalid/StatusTrio-1.5.0.dmg" \
    --ed-signature "new-signature" \
    --length "99"

python3 - "$WORK/original.xml" "$WORK/generated.xml" <<'PY'
import pathlib
import re
import sys
import xml.etree.ElementTree as ET

original = pathlib.Path(sys.argv[1]).read_text()
generated = pathlib.Path(sys.argv[2]).read_text()
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ns = {"sparkle": sparkle, "xml": "http://www.w3.org/XML/1998/namespace"}
items = ET.fromstring(generated).findall("./channel/item")
assert len(items) == 2, f"expected 2 items, got {len(items)}"
new, old = items
assert new.findtext("sparkle:version", namespaces=ns) == "18"
assert new.findtext("sparkle:minimumSystemVersion", namespaces=ns) == "13.0"
assert old.findtext("sparkle:version", namespaces=ns) == "17"
assert old.findtext("sparkle:minimumSystemVersion", namespaces=ns) == "15.0"
old_title = old.find("title[@xml:lang='en']", ns)
new_titles = new.findall("title")
assert new_titles and new_titles[0].attrib.get("{http://www.w3.org/XML/1998/namespace}lang") == "en"
langs = [node.attrib.get("{http://www.w3.org/XML/1998/namespace}lang") for node in new_titles]
assert langs == ["en", "zh-Hans"], f"unexpected title languages: {langs}"
assert new.find("enclosure").attrib[f"{{{sparkle}}}edSignature"] == "new-signature"
assert "old-signature" in generated
assert "sparkle:minimumSystemVersion>15.0<" in original
PY

ruby "$ROOT/scripts/update-appcast.rb" \
    --version 1.5.0 \
    --build 19 \
    --minimum-system-version 13.0 \
    --notes-dir "$notes" \
    --appcast "$WORK/history.xml" \
    --output "$WORK/explicit.xml" \
    --dmg-url "https://example.invalid/StatusTrio-1.5.0.dmg" \
    --ed-signature "explicit-signature" \
    --length "100"
python3 - "$WORK/explicit.xml" <<'PY'
import sys
import xml.etree.ElementTree as ET
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = ET.parse(sys.argv[1]).findall("./channel/item")
assert items[0].findtext("sparkle:minimumSystemVersion", namespaces=ns) == "13.0"
PY

echo "appcast minimum-system-version regression passed"
