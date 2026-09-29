#!/usr/bin/env bats
# End-to-end tests: build real repositories in a temp dir, run logr on them.
# LOGR_BASH picks the interpreter, so CI can also cover macOS's bash 3.2.

bats_require_minimum_version 1.5.0

setup() {
  export GIT_AUTHOR_NAME="Ann Author" GIT_AUTHOR_EMAIL=ann@example.com
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
  LOGR="$BATS_TEST_DIRNAME/../bin/logr"
  cd "$BATS_TEST_TMPDIR"
  mkdir ws
}

logr() {
  "${LOGR_BASH:-bash}" "$LOGR" "$@"
}

# commit REPO MESSAGE [DATE] - an empty commit with that message (and date)
commit() {
  local date="${3:-2026-09-01T12:00:00}"
  GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" \
    git -C "ws/$1" commit -q --allow-empty -m "$2"
}

repo() {
  git init -q -b main "ws/$1"
}

@test "finds commits by message across repositories, in discovery order" {
  repo api; commit api "fix login redirect"; commit api "unrelated"
  repo web; commit web "Login page: fix spacing"
  repo zzz; commit zzz "nothing here"
  run logr login ws
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "api"$'\t'*$'\t'"2026-09-01"$'\t'"Ann Author"$'\t'"main"$'\t'"fix login redirect" ]]
  [[ "${lines[1]}" == "web"$'\t'*$'\t'"Login page: fix spacing" ]]
  [[ "$output" != *"unrelated"* && "$output" != *"nothing here"* ]]
  [[ "$output" == *"2 commits in 2 of 3 repositories"* ]]
}

@test "piped output is tab-separated: repo, commit, date, author, branch, subject" {
  repo api; commit api "add feature"
  run --separate-stderr logr feature ws
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  IFS=$'\t' read -r r sha date author branch subject <<<"${lines[0]}"
  [ "$r" = api ]
  [ "$sha" = "$(git -C ws/api rev-parse --short HEAD)" ]
  [ "$date" = 2026-09-01 ]
  [ "$author" = "Ann Author" ]
  [ "$branch" = main ]
  [ "$subject" = "add feature" ]
  [[ "$stderr" == *"1 commit in 1 of 1 repository"* ]]
}

@test "pattern is literal text: regex characters match themselves" {
  repo r; commit r "fix(login): redirect"; commit r "fix login"
  run logr "fix(login)" ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"fix(login): redirect"* ]]
  [[ "$output" != *$'\t'"fix login"* ]]
}

@test "--regex treats the pattern as an extended regular expression" {
  repo r; commit r "fix login"; commit r "fix logout"; commit r "feat: login"
  run logr -E '^fix log(in|out)$' ws
  [[ "$output" == *"fix login"* && "$output" == *"fix logout"* ]]
  [[ "$output" != *"feat: login"* ]]
}

@test "smart case: lowercase ignores case, a capital makes it exact" {
  repo r; commit r "DIIAP-4555 fix"; commit r "diiap-4555 lower"
  run logr diiap-4555 ws
  [[ "$output" == *"DIIAP-4555 fix"* && "$output" == *"diiap-4555 lower"* ]]
  run logr DIIAP-4555 ws
  [[ "$output" == *"DIIAP-4555 fix"* && "$output" != *"diiap-4555 lower"* ]]
  run logr -i DIIAP-4555 ws
  [[ "$output" == *"diiap-4555 lower"* ]]
  run logr --case-sensitive diiap-4555 ws
  [[ "$output" != *"DIIAP-4555 fix"* ]]
}

@test "searches all branches and says which branch a commit is on" {
  repo r; commit r "base"
  git -C ws/r checkout -q -b feature/login
  commit r "login work in progress"
  git -C ws/r checkout -q main
  run logr "in progress" ws
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *$'\t'"feature/login"$'\t'"login work in progress" ]]
}

@test "finds commits that only exist on a remote-tracking branch" {
  git init -q --bare -b main origin.git
  git clone -q origin.git ws/r 2>/dev/null
  commit r "base" && git -C ws/r push -q origin main
  git clone -q origin.git other 2>/dev/null
  git -C other checkout -q -b colleague
  GIT_AUTHOR_NAME="Bob" git -C other commit -q --allow-empty -m "colleague fix for login"
  git -C other push -q origin colleague
  git -C ws/r fetch -q
  run logr colleague ws
  [ "$status" -eq 0 ]
  [[ "$output" == *$'\t'"Bob"$'\t'"origin/colleague"$'\t'"colleague fix for login"* ]]
}

@test "--current searches only the checked-out branch" {
  repo r; commit r "base login"
  git -C ws/r checkout -q -b other && commit r "other login" && git -C ws/r checkout -q main
  run --separate-stderr logr --current login ws
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *$'\t'"main"$'\t'"base login" ]]
  git -C ws/r checkout -q --detach other
  run --separate-stderr logr --current login ws
  [[ "${lines[0]}" == *$'\t'"HEAD"$'\t'"other login" ]]
}

@test "a commit on several branches is listed once" {
  repo r; commit r "shared login fix"
  git -C ws/r branch copy
  run --separate-stderr logr login ws
  [ "${#lines[@]}" -eq 1 ]
}

@test "--code finds commits that add or remove the text" {
  repo r
  echo 'getUserInfo()' >ws/r/a.js && git -C ws/r add a.js && commit r "add call"
  echo 'other()' >ws/r/a.js && git -C ws/r add a.js && commit r "remove call"
  echo 'x' >ws/r/b.js && git -C ws/r add b.js && commit r "mentions getUserInfo only in message"
  run logr --code getUserInfo ws
  [ "$status" -eq 0 ]
  [[ "$output" == *"add call"* && "$output" == *"remove call"* ]]
  [[ "$output" != *"only in message"* ]]
  run logr -cE 'get[A-Z][a-z]+Info' ws
  [[ "$output" == *"add call"* ]]
}

@test "--author, --since and --until filter commits, alone or with a pattern" {
  repo r
  commit r "old ann" 2026-01-01T12:00:00
  GIT_AUTHOR_NAME=Bob commit r "bob change" 2026-06-01T12:00:00
  commit r "new ann" 2026-09-01T12:00:00
  run logr --author=bob -C ws
  [[ "$output" == *"bob change"* && "$output" != *"ann"* ]]
  run logr '' ws --since 2026-05-01 --until 2026-07-01
  [[ "$output" == *"bob change"* && "$output" != *"old ann"* && "$output" != *"new ann"* ]]
  run logr --author "Ann Author" --since=2026-08-01 -C ws
  [[ "$output" == *"new ann"* && "$output" != *"old ann"* ]]
}

@test "--max-count limits commits per repository" {
  repo a; commit a "login 1"; commit a "login 2"; commit a "login 3"
  repo b; commit b "login b"
  run --separate-stderr logr -m 2 login ws
  [ "${#lines[@]}" -eq 3 ]
  [[ "$output" == *"login 3"* && "$output" == *"login 2"* && "$output" != *"login 1"* ]]
}

@test "on a terminal, results are grouped under each repository" {
  repo api; commit api "fix login"
  repo web; commit web "login page"
  run logr_tty --no-color login ws
  [ "$status" -eq 0 ]
  [[ "$output" == "api
  "*"  2026-09-01  fix login  (Ann Author, main)

web
  "*"  2026-09-01  login page  (Ann Author, main)

2 commits in 2 of 2 repositories"* ]]
}

@test "colors on a terminal, not with NO_COLOR or --no-color" {
  repo r; commit r "login"
  run logr_tty login ws
  [[ "$output" == *$'\e[1mr\e[0m'* ]]
  NO_COLOR=1 run logr_tty login ws
  [[ "$output" != *$'\e['* ]]
  run logr_tty --no-color login ws
  [[ "$output" != *$'\e['* ]]
}

@test "--jobs keeps results in discovery order" {
  for n in a b c d e f; do repo "$n"; commit "$n" "login $n"; done
  run --separate-stderr logr -j 6 login ws
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "a b c d e f " ]
  run --separate-stderr logr -j 1 login ws
  [ "$(printf '%s\n' "${lines[@]}" | cut -f1 | tr '\n' ' ')" = "a b c d e f " ]
}

@test "exit 1 when nothing matches, and on an empty repository" {
  repo r; commit r "something"
  git init -q -b main ws/empty
  run --separate-stderr logr nomatch ws
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [[ "$stderr" == *"0 commits in 0 of 2 repositories"* ]]
}

@test "a git error in one repository is reported and exits 2" {
  repo good; commit good "login"
  repo bad; commit bad "login"
  echo "garbage" >ws/bad/.git/HEAD
  run --separate-stderr logr login ws
  [ "$status" -eq 2 ]
  [[ "$output" == *"good"* ]]
  [[ "$stderr" == *"x bad"* && "$stderr" == *"Failed: bad"* ]]
}

@test "-C DIR and DIR after PATTERN are the same; the default is the current directory" {
  repo r; commit r "login"
  run --separate-stderr logr -C ws login
  [[ "${lines[0]}" == r$'\t'* ]]
  cd ws
  run --separate-stderr logr login
  [[ "${lines[0]}" == r$'\t'* ]]
}

@test "--submodules also searches checked-out submodules" {
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  git init -q --bare -b main lib.git
  git clone -q lib.git libw 2>/dev/null
  git -C libw commit -q --allow-empty -m "lib login fix" && git -C libw push -q origin main
  repo app; commit app "app base"
  git -C ws/app submodule add -q "$BATS_TEST_TMPDIR/lib.git" lib 2>/dev/null
  commit app "add lib"
  run --separate-stderr logr login ws
  [ "$status" -eq 1 ]
  run --separate-stderr logr -s login ws
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "app/lib"$'\t'*"lib login fix" ]]
}

@test "short options combine: -ic, -m1, -im 1" {
  repo r
  echo 'Token' >ws/r/a && git -C ws/r add a && commit r "one"
  echo 'x' >ws/r/a && git -C ws/r add a && commit r "two"
  run --separate-stderr logr -ic TOKEN ws
  [ "${#lines[@]}" -eq 2 ]
  run --separate-stderr logr -icm1 TOKEN ws
  [ "${#lines[@]}" -eq 1 ]
  run --separate-stderr logr -im 1 -c TOKEN ws
  [ "${#lines[@]}" -eq 1 ]
}

@test "options can follow PATTERN and DIR; -- ends options" {
  repo r; commit r "-v flag added"; GIT_AUTHOR_NAME=Bob commit r "bob: flag removed"
  run --separate-stderr logr flag ws --author bob
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"bob: flag removed" ]]
  run --separate-stderr logr -- -v ws
  [ "${#lines[@]}" -eq 1 ]
  [[ "${lines[0]}" == *"-v flag added" ]]
}

@test "rejects bad arguments with exit 2" {
  run logr
  [ "$status" -eq 2 ]
  [[ "$output" == *"Nothing to search for"* ]]
  run logr --code
  [ "$status" -eq 2 ]
  run logr -m 0 x ws
  [ "$status" -eq 2 ]
  run logr --jobs=x x ws
  [ "$status" -eq 2 ]
  run logr -x y ws
  [ "$status" -eq 2 ]
  run logr a ws extra
  [ "$status" -eq 2 ]
  run logr -C ws a ws
  [ "$status" -eq 2 ]
  run logr a does-not-exist
  [ "$status" -eq 2 ]
}

@test "--version prints the package.json version" {
  local expected
  expected="$(sed -n 's/.*"version": "\(.*\)".*/\1/p' "$BATS_TEST_DIRNAME/../package.json")"
  run logr --version
  [ "$output" = "logr $expected" ]
}

# Runs logr with stdout on a pseudo-terminal, so its output decisions see a TTY.
logr_tty() {
  python3 - "${LOGR_BASH:-bash}" "$LOGR" "$@" <<'PY'
import os, subprocess, sys
leader, follower = os.openpty()
proc = subprocess.Popen(sys.argv[1:], stdin=subprocess.DEVNULL, stdout=follower, stderr=follower)
os.close(follower)
out = b""
while True:
    try:
        chunk = os.read(leader, 4096)
    except OSError:  # Linux raises EIO once the child closes its side
        break
    if not chunk:
        break
    out += chunk
sys.stdout.write(out.decode().replace("\r\n", "\n"))
sys.exit(proc.wait())
PY
}
