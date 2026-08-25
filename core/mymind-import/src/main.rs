// SPDX-License-Identifier: MIT

use std::{path::PathBuf, process::ExitCode};

use clap::Parser;
use cuttings_import_mymind::{enrich_existing_links, run, EnrichExistingOptions, RunOptions};

/// Import a mymind export folder into a Cuttings library.
///
/// The command previews by default. Pass --write only after reviewing the
/// planned cards and warnings.
#[derive(Debug, Parser)]
#[command(version, about, verbatim_doc_comment)]
struct Arguments {
    /// Folder created by mymind's "Export my mind" action.
    #[arg(
        long,
        value_name = "FOLDER",
        required_unless_present = "enrich_existing_links",
        conflicts_with = "enrich_existing_links"
    )]
    export: Option<PathBuf>,

    /// Existing Cuttings library folder to receive the imported cards.
    #[arg(long, value_name = "FOLDER")]
    library: PathBuf,

    /// Write the planned cards. Without this flag, no library files change.
    #[arg(long)]
    write: bool,

    /// Show one line per reading, using opaque card and Cuttings IDs only.
    #[arg(long)]
    verbose: bool,

    /// Enrich lightweight links already in the library instead of importing an export.
    #[arg(long, conflicts_with = "offline")]
    enrich_existing_links: bool,

    /// Keep imported links URL-only; do not fetch website metadata or assets.
    #[arg(long)]
    offline: bool,

    /// Maximum concurrent website fetches (each host is capped at two).
    #[arg(long, default_value_t = 24)]
    workers: usize,

    /// Abort unless the existing-link target contains exactly this many readings.
    #[arg(long, requires = "enrich_existing_links")]
    expect_count: Option<usize>,

    /// Abort unless the existing-link target has this SHA-256 digest.
    #[arg(long, requires = "enrich_existing_links", value_name = "SHA256")]
    expect_digest: Option<String>,
}

fn main() -> ExitCode {
    let arguments = Arguments::parse();
    if arguments.enrich_existing_links {
        match enrich_existing_links(EnrichExistingOptions {
            library: arguments.library,
            write: arguments.write,
            verbose: arguments.verbose,
            workers: arguments.workers,
            expected_count: arguments.expect_count,
            expected_digest: arguments.expect_digest,
        }) {
            Ok(report) => {
                print!("{}", report.render());
                if report.errors == 0 {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                }
            }
            Err(error) => {
                eprintln!("link metadata migration failed: {error:#}");
                ExitCode::FAILURE
            }
        }
    } else {
        match run(RunOptions {
            export: arguments
                .export
                .expect("clap requires an export outside migration mode"),
            library: arguments.library,
            write: arguments.write,
            verbose: arguments.verbose,
            enrich_links: !arguments.offline,
            workers: arguments.workers,
        }) {
            Ok(report) => {
                print!("{}", report.render());
                if report.errors == 0 {
                    ExitCode::SUCCESS
                } else {
                    ExitCode::FAILURE
                }
            }
            Err(error) => {
                eprintln!("mymind import failed: {error:#}");
                ExitCode::FAILURE
            }
        }
    }
}
