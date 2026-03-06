r"""
Normalise PURL version encoding and CPE version fields in a Syft-generated
SPDX SBOM.

--- PURL fix ---
spdx-dependency-submission-action@v0.2.0 uses a PURL library whose toString()
outputs ':' and '+' as literal characters in the version component (not
percent-encoded).  Its validator therefore rejects the %3A / %3a and %2B / %2b
that Syft correctly produces per the PURL spec, logging
  "Invalid purl: version must be percent-encoded"
warnings and silently dropping those packages from the dependency graph
submission.

Workaround: decode only %3A/a (':') and %2B/b ('+') in the version segment of
each PACKAGE-MANAGER purl so the action's validator accepts the packages.
The qualifiers (everything after '?') are left untouched.

--- CPE fix ---
Syft writes the full Debian package version (including the epoch prefix and the
Debian revision suffix) into CPE version fields.  For example, the git package
whose dpkg version is "1:2.47.3-0+deb13u1" gets a CPE whose version component
is "1\:2.47.3-0\+deb13u1" (using CPE backslash-escaping for : and +).

The NVD CVE database stores upstream versions without epochs or Debian
revisions (e.g. "2.15.1").  Tools that do CPE-based vulnerability matching may
therefore compare only the epoch digit ("1") against an upstream version range
and incorrectly conclude the package is vulnerable (1 < 2.15.1).

Workaround: rewrite each SECURITY CPE version field to contain only the
upstream version by:
  - stripping the Debian epoch prefix  (e.g. "1\:" at the start)
  - stripping the Debian revision suffix (e.g. "-0\+deb13u1" at the end)

The git CPE above becomes: cpe:2.3:a:git:git:2.47.3:*:*:*:*:*:*:*

Backslash escaping note: CPE special characters are represented as a single
literal backslash followed by the character (e.g. "\:" for a colon).  In the
Python string loaded from JSON this is one backslash character.  In a Python
raw-string regex r"\\" (two characters) compiles to a pattern that matches
exactly one backslash, so r"\d+\\:" matches the epoch prefix "1\:".

Usage: python3 fix-purl-encoding.py <sbom.json>
"""

import json
import re
import sys


def fix_purl_version(purl):
    """Decode %3A/%3a and %2B/%2b in the version part of a PURL (between '@' and '?')."""
    # PURL format: pkg:type[/namespace]/name[@version][?qualifiers][#subpath]
    colon_pos = purl.find(':')
    if colon_pos == -1:
        return purl  # not a valid PURL, leave unchanged
    at_pos = purl.find('@', colon_pos + 1)  # skip the 'pkg:' prefix colon
    if at_pos == -1:
        return purl
    q_pos = purl.find('?', at_pos)
    if q_pos == -1:
        version_raw = purl[at_pos + 1:]
        rest = ''
    else:
        version_raw = purl[at_pos + 1:q_pos]
        rest = purl[q_pos:]
    # Handle both upper- and lower-case percent-encoded forms.
    version_fixed = re.sub(r'%3[Aa]', ':', version_raw)
    version_fixed = re.sub(r'%2[Bb]', '+', version_fixed)
    return purl[:at_pos + 1] + version_fixed + rest


# Match the Debian epoch prefix "N\:" at the start of the CPE version field.
# r"\\" in a raw string is two characters that compile to a regex matching one
# literal backslash, so r"\d+\\:" matches e.g. "1\:" in the Python string.
_CPE_EPOCH_RE = re.compile(r'(cpe:2\.3:[aoh]:[^:]+:[^:]+:)\d+\\:')

# After epoch removal the version may still carry the Debian revision
# ("-N" or "-N+debXuY" etc.) at the end.  Strip it so the CPE version is
# the plain upstream version (e.g. "2.47.3-0\+deb13u1" becomes "2.47.3").
# "[^:-]*" matches the revision characters (non-colon, non-hyphen);
# "(?=:)" anchors the match to the end of the CPE version field.
_CPE_REVISION_RE = re.compile(r'(cpe:2\.3:[aoh]:[^:]+:[^:]+:[^:]*)-[^:-]*(?=:)')


def fix_cpe_version(cpe):
    """Strip Debian epoch and Debian revision from a CPE version field.

    Example: 'cpe:2.3:a:git:git:1\\:2.47.3-0\\+deb13u1:*:...'
         ->  'cpe:2.3:a:git:git:2.47.3:*:...'
    """
    cpe = _CPE_EPOCH_RE.sub(r'\1', cpe)
    cpe = _CPE_REVISION_RE.sub(r'\1', cpe)
    return cpe


def main():
    if len(sys.argv) != 2:
        print(f'Usage: {sys.argv[0]} <sbom.json>', file=sys.stderr)
        sys.exit(1)

    sbom_path = sys.argv[1]

    with open(sbom_path) as f:
        data = json.load(f)

    purl_changed = 0
    cpe_changed = 0
    for pkg in data.get('packages', []):
        for ref in pkg.get('externalRefs', []):
            cat = ref.get('referenceCategory')
            rtype = ref.get('referenceType')
            locator = ref.get('referenceLocator', '')

            if cat == 'PACKAGE-MANAGER' and rtype == 'purl':
                fixed = fix_purl_version(locator)
                if fixed != locator:
                    ref['referenceLocator'] = fixed
                    purl_changed += 1

            elif cat == 'SECURITY' and rtype == 'cpe23Type':
                fixed = fix_cpe_version(locator)
                if fixed != locator:
                    ref['referenceLocator'] = fixed
                    cpe_changed += 1

    print(f'Fixed PURL version encoding in {purl_changed} package(s).')
    print(f'Fixed CPE version (epoch + revision) in {cpe_changed} package(s).')

    with open(sbom_path, 'w') as f:
        json.dump(data, f, indent=2)


if __name__ == '__main__':
    main()
