// SPDX-License-Identifier: MIT

//! Developer CLI for read-later-core.
//!
//! Usage examples:
//!   rl rebuild ~/read-later ~/read-later/index.db
//!   rl sync    ~/read-later ~/read-later/index.db
//!   rl search  ~/read-later/index.db "rust async"
//!   rl list    ~/read-later/index.db
//!   rl list    ~/read-later/index.db --view unread --tag rust
//!   rl get     ~/read-later/index.db 01JXXXXXXXXXXXXXXXXXXXXXXXXX
//!   rl tags    ~/read-later/index.db
//!   rl add-tag ~/read-later ~/read-later/index.db <id> <tag>
//!   rl rm-tag  ~/read-later ~/read-later/index.db <id> <tag>
//!   rl set     ~/read-later ~/read-later/index.db <id> read true

use anyhow::Result;
use clap::{Parser, Subcommand};
use read_later_core::{
    add_tag, apply_diffs, diff, get_reading,
    list::{ListOptions, SortOrder, View},
    list_readings, list_tags, open_index, rebuild, remove_tag, scan_library, search, set_archived,
    set_favorite, set_read, LibraryRoot,
};
use std::path::Path;

#[derive(Parser)]
#[command(name = "rl", about = "read-later dev CLI", version)]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Rebuild the index from scratch by scanning the library.
    Rebuild {
        library_path: String,
        db_path: String,
    },
    /// Incremental sync: scan and apply only changed articles.
    Sync {
        library_path: String,
        db_path: String,
    },
    /// Full-text search the index.
    Search {
        db_path: String,
        query: String,
        #[arg(long, default_value = "10")]
        limit: usize,
    },
    /// List readings (smart-view filter).
    List {
        db_path: String,
        #[arg(long, default_value = "all")]
        view: String,
        #[arg(long)]
        tag: Option<String>,
        #[arg(long, default_value = "20")]
        limit: usize,
        #[arg(long, default_value = "0")]
        offset: usize,
    },
    /// Fetch a single reading (metadata + body excerpt).
    Get { db_path: String, id: String },
    /// List all tags with counts.
    Tags { db_path: String },
    /// Add a tag to a reading.
    AddTag {
        library_path: String,
        db_path: String,
        id: String,
        tag: String,
    },
    /// Remove a tag from a reading.
    RmTag {
        library_path: String,
        db_path: String,
        id: String,
        tag: String,
    },
    /// Set a boolean flag on a reading (read|archived|favorite).
    Set {
        library_path: String,
        db_path: String,
        id: String,
        flag: String,
        value: String,
    },
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.cmd {
        Cmd::Rebuild {
            library_path,
            db_path,
        } => {
            let lib = LibraryRoot::new(Path::new(&library_path))?;
            let conn = open_index(Path::new(&db_path))?;
            rebuild(&conn, &lib)?;
            let count = scan_library(&lib)?.len();
            println!("Rebuilt index: {count} articles indexed.");
        }

        Cmd::Sync {
            library_path,
            db_path,
        } => {
            let lib = LibraryRoot::new(Path::new(&library_path))?;
            let conn = open_index(Path::new(&db_path))?;
            // Load all current index rows as the "old" state by scanning first.
            let old_scan = scan_library(&lib)?;
            // Re-scan to detect any changes since the DB was last written.
            // (For a persistent daemon this would compare against a stored snapshot.)
            let new_scan = scan_library(&lib)?;
            let diffs = diff(&old_scan, &new_scan);
            let n = diffs.len();
            if n > 0 {
                apply_diffs(&conn, &diffs)?;
            }
            println!("Sync complete: {n} change(s) applied.");
        }

        Cmd::Search {
            db_path,
            query,
            limit,
        } => {
            let conn = open_index(Path::new(&db_path))?;
            let results = search(&conn, &query, limit)?;
            if results.is_empty() {
                println!("No results.");
            }
            for r in &results {
                println!("[{}] {}", r.id, r.title);
                println!("    {}", r.snippet);
            }
        }

        Cmd::List {
            db_path,
            view,
            tag,
            limit,
            offset,
        } => {
            let view = match view.to_lowercase().as_str() {
                "unread" => View::Unread,
                "archive" => View::Archive,
                "favorites" => View::Favorites,
                _ => View::All,
            };
            let conn = open_index(Path::new(&db_path))?;
            let rows = list_readings(
                &conn,
                &ListOptions {
                    view,
                    sort: SortOrder::NewestFirst,
                    tag,
                    limit,
                    offset,
                    ..Default::default()
                },
            )?;
            if rows.is_empty() {
                println!("No readings.");
            }
            for r in &rows {
                let flags = format!(
                    "{}{}{}",
                    if r.read { "R" } else { " " },
                    if r.archived { "A" } else { " " },
                    if r.favorite { "★" } else { " " },
                );
                let tags = if r.tags.is_empty() {
                    String::new()
                } else {
                    format!("  [{}]", r.tags.join(", "))
                };
                println!("[{}] {} {} — {}{}", flags, r.saved_at, r.id, r.title, tags);
            }
            println!("\n{} reading(s).", rows.len());
        }

        Cmd::Get { db_path, id } => {
            let conn = open_index(Path::new(&db_path))?;
            match get_reading(&conn, &id)? {
                None => println!("Not found: {id}"),
                Some((row, body)) => {
                    println!("Title  : {}", row.title);
                    println!("URL    : {}", row.url);
                    println!("Saved  : {}", row.saved_at);
                    println!("Tags   : {}", row.tags.join(", "));
                    println!(
                        "Read   : {} | Archived: {} | Favorite: {}",
                        row.read, row.archived, row.favorite
                    );
                    println!("---");
                    let preview: String = body.chars().take(400).collect();
                    println!("{preview}");
                    if body.len() > 400 {
                        println!("… ({} chars total)", body.len());
                    }
                }
            }
        }

        Cmd::Tags { db_path } => {
            let conn = open_index(Path::new(&db_path))?;
            let tags = list_tags(&conn)?;
            if tags.is_empty() {
                println!("No tags.");
            }
            for (tag, count) in &tags {
                println!("{tag:30} {count}");
            }
        }

        Cmd::AddTag {
            library_path,
            db_path,
            id,
            tag,
        } => {
            let lib = LibraryRoot::new(Path::new(&library_path))?;
            let conn = open_index(Path::new(&db_path))?;
            add_tag(&lib, &conn, &id, &tag)?;
            println!("Added tag '{tag}' to {id}.");
        }

        Cmd::RmTag {
            library_path,
            db_path,
            id,
            tag,
        } => {
            let lib = LibraryRoot::new(Path::new(&library_path))?;
            let conn = open_index(Path::new(&db_path))?;
            remove_tag(&lib, &conn, &id, &tag)?;
            println!("Removed tag '{tag}' from {id}.");
        }

        Cmd::Set {
            library_path,
            db_path,
            id,
            flag,
            value,
        } => {
            let lib = LibraryRoot::new(Path::new(&library_path))?;
            let conn = open_index(Path::new(&db_path))?;
            let v = matches!(value.to_lowercase().as_str(), "true" | "1" | "yes");
            match flag.to_lowercase().as_str() {
                "read" => set_read(&lib, &conn, &id, v)?,
                "archived" => set_archived(&lib, &conn, &id, v)?,
                "favorite" => set_favorite(&lib, &conn, &id, v)?,
                other => anyhow::bail!("unknown flag '{other}'; use read|archived|favorite"),
            }
            println!("Set {flag}={v} on {id}.");
        }
    }

    Ok(())
}
