# logr

[![CI](https://github.com/kova1max/logr/actions/workflows/ci.yml/badge.svg)](https://github.com/kova1max/logr/actions/workflows/ci.yml)
[![npm](https://img.shields.io/npm/v/%40kova1%2Flogr?logo=npm&label=npm)](https://www.npmjs.com/package/@kova1/logr)
[![Homebrew](https://img.shields.io/github/v/release/kova1max/logr?logo=homebrew&label=homebrew)](https://github.com/kova1max/homebrew-tap)
[![License: MIT](https://img.shields.io/github/license/kova1max/logr)](LICENSE)

Search the commit history of every git repository under a directory.

Built for workspaces made of many independent repositories, where "which
repos did that ticket touch?" means running `git log --grep` in each one.

```console
$ logr PROJ-142 ~/work
api
  3f9c2a1  2026-09-23  PROJ-142: validate redirect URL  (Ann Lee, main)
  b71e0d4  2026-09-22  PROJ-142: add failing test  (Ann Lee, origin/fix/PROJ-142)

web
  c02a9f7  2026-09-24  Merge branch 'fix/PROJ-142' into 'main'  (Bob Stone, origin/main)

3 commits in 2 of 14 repositories
```

## Install

```sh
# Homebrew
brew install kova1max/tap/logr

# npm
npm install -g @kova1/logr
```

To try it without installing anything:

```sh
npx @kova1/logr PROJ-142 ~/work
```

Every release is also mirrored to
[GitHub Packages](https://github.com/kova1max/logr/pkgs/npm/logr) as
`@kova1max/logr` (GitHub requires the repo owner as scope). Installing from
there needs a GitHub token, so the npm registry above is the easier choice.

## What it will never do

logr only reads. It will never:

- **Fetch, pull or touch the network.** It searches what is already on disk,
  so it is instant and works offline. To include your colleagues' latest
  commits, fetch first (for example with
  [pullr](https://github.com/kova1max/pullr)).
- **Change a repository** - no checkouts, no writes to `.git`, no changes to
  the working tree.
- **Enter a nested repository**, unless it is a submodule and you ask for
  submodules with `--submodules`.
- **Follow symlinked directories.**

## Usage

```
logr [options] [PATTERN] [DIR]
```

`PATTERN` is literal text, matched against the whole commit message. Lowercase
text matches any case; text with a capital letter matches exactly (smart
case), so `logr login` finds "Login" while `logr PROJ-142` does not find
"proj-142".

Every local and remote-tracking branch is searched, and each commit is listed
once, with the branch it was found on. Options can go before or after
`PATTERN` and `DIR`.

Short options can be combined: `-ic` is `-i -c`, and `-m5` or `-im 5` set the count.

| Option&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Default | Meaning |
| :--- | :--- | :--- |
| `DIR`, `-C DIR` | current&nbsp;directory | Where to look for repositories |
| `-E`, `--regex` | | Treat `PATTERN` as an extended regular expression |
| `-i`, `--ignore-case` | smart case | Always ignore case |
| `--case-sensitive` | smart case | Never ignore case |
| `-c`, `--code` | | Search the changes instead of the messages: list the commits that add or remove `PATTERN` (`git log -S`, or `-G` with `--regex`). Slower on large histories. |
| `--author WHO` | | Only commits by an author whose name or email matches `WHO` |
| `--since DATE` | | Only commits after `DATE`, e.g. `2026-09-01` or `2.weeks` |
| `--until DATE` | | Only commits before `DATE` |
| `--current` | | Only search the checked-out branch of each repository |
| `-m`, `--max-count N` | | Show at most `N` commits per repository |
| `-j`, `--jobs N` | `8` | Search up to `N` repositories in parallel. Output is printed in discovery order, so it reads the same as a sequential run. |
| `--max-depth N` | `2` | How many directory levels below `DIR` to search. `0` = only `DIR` itself, `1` = `DIR` and its direct children, ... |
| `-s`, `--submodules` | off | Also search each checked-out submodule |
| `--no-color` | | Disable colored output. Also disabled when the [`NO_COLOR`](https://no-color.org) environment variable is set, or when output is not a terminal. |
| `-V`, `--version` | | Print the version |
| `-h`, `--help` | | Show help |

`PATTERN` can be left out when searching only by `--author`, `--since` or
`--until`; pass `''` in its place when also giving `DIR`.

### Examples

```sh
# every commit that mentions a ticket
logr PROJ-142 ~/work

# what Ann committed in the last week
logr '' ~/work --author ann --since 1.week

# recent reverts, searching from the current directory
logr -E 'revert|rollback' --since 1.month

# the commits that added or removed a call
logr -c getUserInfo ~/work

# the latest release commit on each checked-out branch
logr -m 1 --current release
```

### Output

On a terminal, commits are grouped under each repository, newest first, as
in the example at the top. When the output is piped, each commit is one
tab-separated line - repository, commit, date, author, branch, subject - so it
works with `cut`, `sort` and `awk`:

```console
$ logr PROJ-142 ~/work | cut -f1 | sort -u
api
web
```

The summary line and any errors go to stderr, so piped output stays pure data.
Exits `0` if any commit matched, `1` if none did, and `2` on invalid arguments
or if a repository could not be searched, like `grep`.

## License

[MIT](LICENSE)
