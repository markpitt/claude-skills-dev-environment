#!/usr/bin/env bash
# Exercise the hooks against a throwaway bare remote. Touches nothing outside a temp dir and
# does not need the hooks to be installed. Exit 0 when every case behaves.
set -u
here=$(dirname "$(readlink -f "$0")")
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
H=$T/hooks; mkdir -p "$H"
cp "$here/pre-push" "$here/_chain" "$H/"; chmod 755 "$H/pre-push" "$H/_chain"; ln -s _chain "$H/pre-commit"
fail=0
check() {  # check <description> <expected rc> <actual rc>
  if [ "$2" = "$3" ]; then echo "ok    $1"; else echo "FAIL  $1 (rc $3, wanted $2)"; fail=1; fi
}
G() { git -c core.hooksPath="$H" "$@"; }

cd "$T"
git init -q --bare -b main remote.git
git clone -q remote.git w 2>/dev/null; cd w
git config user.email t@example.com; git config user.name tester; git checkout -q -b main

echo a >f; git add f; G commit -qm one
G push -q origin HEAD:main >/dev/null 2>&1;            check "first push to an empty remote"   0 $?
echo b >>f; G commit -qam two
G push -q origin HEAD:main >/dev/null 2>&1;            check "fast-forward push"               0 $?
git reset -q --hard HEAD~1; echo c >>f; G commit -qam diverged
G push -q origin HEAD:main >/dev/null 2>&1;            check "diverged push (git itself)"      1 $?
G push --force origin HEAD:main >/dev/null 2>&1;       check "--force refused"                 1 $?
G push --force-with-lease origin HEAD:main >/dev/null 2>&1; check "--force-with-lease refused" 1 $?
G push origin +HEAD:main >/dev/null 2>&1;              check "+refspec refused"                1 $?
G push -q origin HEAD:topic >/dev/null 2>&1;           check "new branch allowed"              0 $?
G push -q origin :topic >/dev/null 2>&1;               check "branch deletion allowed"         0 $?
[ "$(git --git-dir=../remote.git log --format=%s main | tr '\n' ' ')" = "two one " ]
check "remote history intact after the refused pushes" 0 $?

git fetch -q origin; git reset -q --hard origin/main; echo d >>f; G commit -qam three
printf '#!/bin/sh\nexit 1\n' >.git/hooks/pre-push; chmod +x .git/hooks/pre-push
G push -q origin HEAD:main >/dev/null 2>&1;            check "repo-local pre-push is chained"  1 $?
rm .git/hooks/pre-push
printf '#!/bin/sh\nexit 1\n' >.git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
echo e >>f; G commit -qam four >/dev/null 2>&1;        check "repo-local pre-commit is chained" 1 $?

[ "$fail" = 0 ] && echo "all passed" || echo "FAILED"
exit "$fail"
