# todotui

A terminal UI for the [todo.txt](https://github.com/todotxt/todo.txt) format,
built on [ruby-tui](https://github.com/adiprnm/ruby-tui).

```
╭  todotui  ───────────────────────────────────────────────────────────────────────────────────────╮
│Filter  text, +project, @context…                 ( ) All  (•) Open  ( ) Done      6 open · 1 done│
│╭ Tasks ─────────────────────────────────────── 6 shown · smart ╮╭ Details ──────────────── open ╮│
││     P  DUE          TASK                + / @                 ││Line      (A) 2026-09-27 Pay   ││
││───────────────────────────────────────────────────────────────││          the electricity bill ││
││    (A) 2026-10-08   Pay the electricit… +home                 ││          +home due:2026-10-08 ││
││    (B) 2026-10-16   Ship the todo.txt … +work @laptop         ││Status    open                 ││
││    (C) 2026-10-26   Plan the weekend t… +travel @home         ││Priority  (A)                  ││
││        2026-10-06 • Buy milk and eggs … +errands @market      ││Created   2026-09-27           ││
││                     Back up laptop t:2… +maintenance @laptop  ││Completed —                    ││
││                     Read the todo.txt … +reading              ││Due       2026-10-08 (in 2d)   ││
│╰───────────────────────────────────────────────────────────────╯╰───────────────────────────────╯│
│Demo data (not saved)                                                                             │
╰──────────────────────────────────────────────────────────────────────────────────────────────────╯
```

## Requirements

* Ruby (developed against 3.4, the toolkit supports older versions)
* Bundler

## Install

The TUI toolkit is pulled straight from GitHub by Bundler:

```ruby
# Gemfile
gem 'ruby-tui', github: 'adiprnm/ruby-tui'
```

```sh
bundle install
```

## Run

```sh
bundle exec ruby bin/todotui            # open the configured todo.txt
bundle exec ruby bin/todotui --file=~/work/todo.txt
bundle exec ruby bin/todotui --snapshot --demo   # one frame, no terminal needed
bundle exec ruby bin/todotui --theme=plain
```

Or, as a plain script:

```sh
bundle exec ruby todotui.rb
```

To run `todotui` from any directory, link the launcher somewhere on your
`$PATH`. The script resolves symlinks, so the checkout is found no matter
where you call it from:

```sh
ln -s "$(pwd)/bin/todotui" ~/.local/bin/todotui
ln -s "$(pwd)/bin/todotui" ~/.local/bin/tt        # short alias
cd /tmp && todotui
cd /tmp && tt
```

## Standalone binary (Spinel)

The app can be ahead-of-time compiled to a single native binary with
[Spinel](https://github.com/matz/spinel). Bundler cannot be compiled, so the
load paths are passed on the command line instead:

```sh
spinel bin/todotui.spinel.rb -o tt -I lib -I /path/to/ruby-tui/lib
./tt --snapshot --demo
```

or, from the checkout, `rake spinel` (it looks for a sibling
`../ruby-tui`; override with `RUBY_TUI_LIB=...`, rename with `OUT=...`).

The toolkit needs a few small patches to compile under Spinel — the
`lib/tui` sources in the `ruby-tui` checkout already carry them:

* `break` inside iterator blocks is replaced with `catch`/`throw` or
  bounded loops (Spinel rejects `break` outside a real loop);
* `Term.session` sets raw mode via `stty` instead of `IO#raw`, which
  Spinel's `io/console` does not implement (and `IO#ioctl` is missing too);
* `String#each_char` is replaced with `split('')`, since Spinel only
  lowers `each_char` for statically known strings;
* `alias == eql?` is written out as `def ==`, and `Theme::THEMES` is moved
  out of `class << self` (Spinel resolves singleton-class constants as nil);
* terminal output goes through `Term.write`/`Term.flush`, which route the
  real terminal via `$stdout` (Spinel only lowers `IO#print` for a
  statically known IO, so a dynamic sink lost interactive output).

todotui carries its own part: calendar math goes through
`Todotui::Calendar` (Spinel has no `date` stdlib) and the entry point is
`bin/todotui.spinel.rb` rather than the Bundler wrapper.

## Where todo.txt lives

This is the one thing the app is opinionated about: **you can put `todo.txt`
anywhere**, and there are four ways to say where, in order of precedence:

| # | Source | How |
| - | ------ | --- |
| 1 | command line | `todotui --file=~/work/todo.txt` (this run only) |
| 2 | environment   | `TODOTXT_FILE=~/work/todo.txt todotui` |
| 3 | config file   | press `,` in the app and type a path |
| 4 | default       | `~/todo.txt` |

The config file is a tiny key=value file under the XDG config directory:

```
$ cat ~/.config/todotui/config
# todotui configuration
# where your todo.txt and done.txt live
todo_file=/home/you/work/todo.txt
done_file=/home/you/work/done.txt
```

The archive target (`A` key) is configured the same way: `--done-file=PATH`,
`TODOTXT_DONE_FILE`, the `done.txt` field in Settings, or — when nothing is
set — `done.txt` next to the todo.txt in effect.

> Only the namespaced `TODOTXT_FILE` / `TODOTXT_DONE_FILE` variables are
> read. Generic names like `TODO_FILE` are used by other todo.txt tools
> (`todo.sh`) and are deliberately ignored, so they cannot silently override
> the path you set in the config.

Pressing `,` opens the **Settings** dialog. The paths you type there are
written to that config file, so the next launch opens them — no flags or
environment variables needed. `Config#resolve` / `Config#resolve_done` are
the single places the precedence is applied, and they are covered by the
tests.

The file itself is only created when you save your first task, and writes go
through a temp file + rename, so an interrupted save never truncates it.

## todo.txt support

Every line is a task, and the app understands the format:

```text
(A) 2024-01-01 Call mom +family @phone due:2024-02-01
x 2024-02-02 2024-01-01 Call mom +family @phone
```

* optional priority `(A)`..`(Z)` on open tasks
* completion with `x`, the completion date and the optional creation date
* `+project` and `@context` words
* `key:value` metadata such as `due:`, `t:` and `rec:`
* lines that are not touched round-trip byte for byte

The app derives a **due** column from `due:`, flags overdue tasks with `!` and
tasks due today with `•`, and counts open vs. done in the toolbar. Every
priority `A`..`Z` gets its own colour: the whole task line is tinted, and
the details panel shows the priority in the same colour.

## Keys

| key | action |
| --- | ------ |
| `a` | add a task |
| `space` | complete / reopen the selected task |
| `enter` / `e` | edit the selected task |
| `d` | delete (then `u` undoes it) |
| `u` | undo the last delete |
| `j` / `k`, arrows | move the selection |
| `s` | cycle the sort: smart, due, priority, a-z, created, completed |
| `/` | jump to the filter |
| `,` | settings (where `todo.txt` lives) |
| `A` | archive completed tasks to the configured `done.txt` |
| `esc` | cancel a dialog / clear the filter |
| `q` / `ctrl-c` | quit |

Inside a dialog: `enter` saves, `tab` moves between fields, `esc` cancels.
`ctrl-c` quits even while a text field has the focus.

## Tests

```sh
bundle exec ruby test/run.rb
```

49 tests cover the parser and round-tripping, the file store, the config
precedence, filtering/sorting, the app's add/complete/delete/undo/settings
flows, layout at several terminal sizes, and one end-to-end session typed
through a real pty.

## Layout

```
bin/todotui             entry point (bundler + load path + CLI)
bin/todotui.spinel.rb   entry point for the Spinel AOT build
todotui.rb              same, as a plain script
lib/todotui.rb          requires everything
lib/todotui/
  version.rb
  calendar.rb           date helpers built on Time (works under Spinel)
  task.rb               todo.txt line <-> Task, projects/contexts/metadata
  store.rb              load/save/archive a todo.txt file
  config.rb             the config file and path precedence
  query.rb              filtering and sorting
  app.rb                the widget tree and behaviour
  table.rb              the task table, with a colour per priority
  cli.rb                options, the interactive loop, --snapshot
test/                   minitest suite
```
