// SPDX-License-Identifier: MIT

use std::{path::PathBuf, process::ExitCode};

use clap::Parser;
use cuttings_import_mymind::{run, RunOptions};

/// Import a mymind export folder into a Cuttings library.
///
/// The command previews by default. Pass --write only after reviewing the
/// planned cards and warnings.
#[derive(Debug, Parser)]
#[command(version, about, verbatim_doc_comment)]
struct Arguments {
    /// Folder created by mymind's "Export my mind" action.
    #[arg(long, value_name = "FOLDER")]
    export: PathBuf,

    /// Existing Cuttings library folder to receive the imported cards.
    #[arg(long, value_name = "FOLDER")]
    library: PathBuf,

    /// Write the planned cards. Without this flag, no library files change.
    #[arg(long)]
    write: bool,

    /// Show one line per reading, using opaque card and Cuttings IDs only.
    #[arg(long)]
    verbose: bool,
}

fn main() -> ExitCode {
    let arguments = Arguments::parse();
    match run(RunOptions {
        export: arguments.export,
        library: arguments.library,
        write: arguments.write,
        verbose: arguments.verbose,
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
