<h1 align="center">Situ</h1>
<p align="center">Your notes, in situ.</p>

> **in situ** _(adv.)_: in the natural or original position or place.

## What is Situ?

Notes about your code usually live somewhere else—a separate folder, an app, a wiki—and drift out of date because they are out of sight. Situ keeps your notes in the repo, next to the files they describe, and indexes them so they're searchable and stay linked to the code.

- Plain Markdown or Typst files, edited in your own editor
- Sidecar notes that sit beside the file they describe (`parser.situ.md` next to `parser.zig`)
- Anchors that point into code and get flagged when they break (`situ check`)
- A full-text search index that can be rebuilt at any time

Situ is early. v0.1.0 covers workspace setup; the rest is on the [roadmap](#roadmap).

## Install

macOS only for now. Download the [latest release](https://github.com/jefflayton/situ/releases) from GitHub.

To build from source, you need Zig 0.16.0:

```sh
zig build
```

The binary is written to `zig-out/bin/`.

## Roadmap

|  #  | Step                                                                          | Status      |
| :-: | ----------------------------------------------------------------------------- | ----------- |
|  1  | [Project and workspace initialization](#project-and-workspace-initialization) | Done        |
|  2  | [Note reconciliation](#note-reconciliation)                                   | In progress |
|  3  | [TODOs and language server](#todos-and-language-server)                       | Planned     |
|  4  | [Cloud sync and web editor](#cloud-sync-and-web-editor)                       | Planned     |
|  5  | [Referenceable anchors](#referenceable-anchors)                               | Planned     |
|  6  | Linux and Windows support                                                     | Planned     |

### Project and workspace initialization

- A **project** is the top-level container. Each project has its own local database, so related repos can share one.
- A **workspace** is a set of notes and TODOs inside a project. `situ init` attaches the current directory to a workspace, and more than one directory (a second clone, a worktree) can attach to the same workspace.

Run `situ init` in your project directory to:

1. Select or create a project
1. Select or create a workspace
1. Generate a `situ.toml`

### Note reconciliation

Every `situ` command starts by scanning the notes in your workspace, recording what changed since the last run, and adding those changes to a history log.

- `situ status` shows which notes were created, modified, or deleted
- `situ ls` lists every note in your workspace and project

### TODOs and language server

_Details are still being worked out._

Create, edit, and delete TODOs for a workspace.

A language server lets your editor find and index TODO comments in your codebase. For example, your editor would flag the comment below as an actionable item:

```zig
// TODO: setup deinit
fn deinit(self: *Self) void {}
```

### Cloud sync and web editor

`situ push` syncs your notes and TODOs to the cloud. Situ records every change, so conflicting edits from different devices can be detected and resolved instead of overwritten.

A web editor lets you manage notes and TODOs from anywhere, and changes sync back to your devices.

### Referenceable anchors

Code changes often, so a note that points at "line 42" goes stale fast. Anchors mark a region of code with a named _start_ and _end_ comment, and notes reference the name instead of line numbers:

```zig
// situ:start uuid-sqlite-bind
/// Used by sqlite to bind Uuid to Blob type
pub fn bindField(self: UuidCol, alloc: std.mem.Allocator) !BaseType {
    const buf = try alloc.dupe(u8, &self.inner.bytes);
    return .{ .data = buf };
}
// situ:end uuid-sqlite-bind
```

A note can then link to that region:

```markdown
A custom function was required to bind the UUID columns to the SQLite format:
[UUID SQLite Binding](code:jefflayton/situ/src/store/sqlite/row.zig#uuid-sqlite-bind)
```

## License

[MIT](LICENSE)
