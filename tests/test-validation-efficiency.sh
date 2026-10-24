#!/usr/bin/env bash
# test-validation-efficiency.sh — behavior-level checks for declared-scope evidence reuse.
# Uses isolated temporary Git repositories only. bash 3.2+, no frameworks.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/lib/validation-efficiency.sh"

pass=0; failn=0
ok() { pass=$((pass + 1)); echo "PASS: $1"; }
bad() { failn=$((failn + 1)); echo "FAIL: $1"; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

newrepo() {
  local d="$TMP/repo$1"
  rm -rf "$d"
  mkdir -p "$d"
  cd "$d"
  git init -q
  git config user.email "test@example.com"
  git config user.name "Test"
  echo "init" >README
  git add README
  git commit -q -m "C1"
  echo "C1=$(git rev-parse HEAD)" >&2
}

mkcommit() {
  local msg="$1"; shift
  for f in "$@"; do
    mkdir -p "$(dirname "$f")"
    echo "content $msg $f" >"$f"
    git add "$f"
  done
  git commit -q -m "$msg"
  git rev-parse HEAD
}

source "$LIB"

CMD="npm test"
SCOPE="src/"
LABEL="[observed]"
TOOL="node 20"
ENV="CI=true"

# 1. Unchanged evidence can be reused
newrepo 1
C1=$(git rev-parse HEAD)
mkcommit C2 docs/unchanged.txt >/dev/null
C2=$(git rev-parse HEAD)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE" "" "$TOOL" "$TOOL" "$ENV" "$ENV")
case "$out" in reused*) ok "1 unchanged evidence reused" ;; *) bad "1 unchanged evidence reused ($out)" ;; esac

# 2. Non-ancestor evidence is stale
newrepo 2
C1=$(git rev-parse HEAD)
mkcommit C2 a.txt >/dev/null
C2=$(git rev-parse HEAD)
# Make C1 not an ancestor of a new orphan commit? Simpler: final is C1, evidence is C2.
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C2" "$C1" "$SCOPE" "$SCOPE")
case "$out" in *not?an?ancestor*) ok "2 non-ancestor evidence stale" ;; *) bad "2 non-ancestor evidence stale ($out)" ;; esac

# 3. Changed file inside declared scope invalidates evidence
newrepo 3
C1=$(git rev-parse HEAD)
mkcommit C2 src/changed.txt >/dev/null
C2=$(git rev-parse HEAD)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in stale*) ok "3 changed scope file invalidates evidence" ;; *) bad "3 changed scope file invalidates evidence ($out)" ;; esac

# 4. Changed dependency surface invalidates evidence
newrepo 4
C1=$(git rev-parse HEAD)
echo "src/a.py -> src/b.py" >deps.txt
git add deps.txt
git commit -q -m "add deps"
C1b=$(git rev-parse HEAD)
mkcommit C2 src/a.txt >/dev/null
C2=$(git rev-parse HEAD)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1b" "$C2" "$SCOPE" "$SCOPE" "deps.txt")
case "$out" in stale*dependency*) ok "4 changed dependency surface invalidates evidence" ;; *) bad "4 changed dependency surface invalidates evidence ($out)" ;; esac

# 5. Missing scope declaration defaults to repository-wide coverage
newrepo 5
C1=$(git rev-parse HEAD)
mkcommit C2 docs/readme.md >/dev/null
C2=$(git rev-parse HEAD)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "" "")
case "$out" in stale*repository-wide*) ok "5 missing scope defaults repository-wide" ;; *) bad "5 missing scope defaults repository-wide ($out)" ;; esac

# 6. Unknown evidence validity fails closed
newrepo 6
C1=$(git rev-parse HEAD)
C2=$(mkcommit C2 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" unknown "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in stale*result=unknown*) ok "6 unknown result fails closed" ;; *) bad "6 unknown result fails closed ($out)" ;; esac

# 7. Targeted validation: touched scope re-run, untouched scope reused
newrepo 7
C1=$(git rev-parse HEAD)
mkcommit C2 src/auth.js >/dev/null
C2=$(git rev-parse HEAD)
out1=$(decide_evidence_reuse "unit:auth" "unit:auth" passed "$LABEL" "$C1" "$C2" "src/auth.js" "src/auth.js")
out2=$(decide_evidence_reuse "unit:reports" "unit:reports" passed "$LABEL" "$C1" "$C2" "src/reports/" "src/reports/")
case "$out1" in reused*) bad "7 touched scope should be stale ($out1)" ;; *) ok "7 touched scope marked stale" ;; esac
case "$out2" in reused*) ok "7 untouched scope reused" ;; *) bad "7 untouched scope should be reused ($out2)" ;; esac

# 8. Failed evidence is never reused
newrepo 8
C1=$(git rev-parse HEAD)
C2=$(mkcommit C8 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" "failed(unexplained)" "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in stale*result=failed*) ok "8 failed evidence not reused" ;; *) bad "8 failed evidence not reused ($out)" ;; esac

# 9. Command mismatch fails closed
newrepo 9
C1=$(git rev-parse HEAD)
C2=$(mkcommit C9 src/x.txt)
out=$(decide_evidence_reuse "npm test" "npm run test" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in stale*command*) ok "9 command mismatch stale" ;; *) bad "9 command mismatch stale ($out)" ;; esac

# 10. Scope declaration change fails closed
newrepo 10
C1=$(git rev-parse HEAD)
C2=$(mkcommit C10 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "src/" "src/ tests/")
case "$out" in stale*scope*) ok "10 scope declaration change stale" ;; *) bad "10 scope declaration change stale ($out)" ;; esac

# 11. Non-observed label fails closed
newrepo 11
C1=$(git rev-parse HEAD)
C2=$(mkcommit C11 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "[reported]" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in stale*label*) ok "11 non-observed label stale" ;; *) bad "11 non-observed label stale ($out)" ;; esac

# 12. Tool version change fails closed
newrepo 12
C1=$(git rev-parse HEAD)
C2=$(mkcommit C12 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE" "" "$TOOL" "node 22" "$ENV" "$ENV")
case "$out" in stale*tool_version*) ok "12 tool version change stale" ;; *) bad "12 tool version change stale ($out)" ;; esac

# 13. Environment fingerprint change fails closed
newrepo 13
C1=$(git rev-parse HEAD)
C2=$(mkcommit C13 src/x.txt)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE" "" "$TOOL" "$TOOL" "$ENV" "CI=false")
case "$out" in stale*env*) ok "13 env fingerprint change stale" ;; *) bad "13 env fingerprint change stale ($out)" ;; esac

# 14. Missing tool/env still reuses when scope is unchanged (conditions are unverifiable, not false)
newrepo 14
C1=$(git rev-parse HEAD)
C2=$(mkcommit C14 docs/readme.md)
out=$(decide_evidence_reuse "$CMD" "$CMD" passed "$LABEL" "$C1" "$C2" "$SCOPE" "$SCOPE")
case "$out" in reused*) ok "14 empty tool/env reused when scope unchanged" ;; *) bad "14 empty tool/env reused when scope unchanged ($out)" ;; esac

echo
echo "Summary: $pass passed, $failn failed"
[ "$failn" -eq 0 ]
