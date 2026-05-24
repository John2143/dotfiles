use std::{process::Command, time::Duration};

use clap::{Parser, ValueEnum};

mod bindings;

/// macro multiplexer
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    #[arg(short, long, default_value = "tap")]
    key_type: KeyType,

    key_name: String,
}

#[derive(ValueEnum, Debug, Clone)]
enum KeyType {
    Tap,
    Hold,
}

#[derive(thiserror::Error, Debug)]
enum CommandLineError {
    #[error("Invalid key + modifer combo: {kt:?} '{kn}'")]
    InvalidKeyCombo { kt: KeyType, kn: String },
}

#[derive(thiserror::Error, Debug)]
enum InternalError {
    #[error("Invalid program: {0}")]
    InvalidProgram(String),
}

fn run_program_simple_no_send(text: &str) -> anyhow::Result<std::process::Output> {
    let (cmd, args) = text
        .split_once(" ")
        .ok_or_else(|| InternalError::InvalidProgram(text.into()))?;

    Ok(Command::new(cmd).args(args.split(" ")).output()?)
}

/// Short for "run program, notify results"
pub fn rpn(text: &str) -> anyhow::Result<()> {
    let out = run_program_simple_no_send(text)?;
    let stdout = String::from_utf8_lossy(&out.stdout);

    run_program_simple_no_send(&*format!("notify-send {}", stdout.trim()))?;
    Ok(())
}

pub fn rpn_wait(delay_ms: u64, text: &str) -> anyhow::Result<()> {
    std::thread::sleep(Duration::from_millis(delay_ms));
    rpn(text)
}

/// Short for "run program".
pub fn rp(text: &str) -> anyhow::Result<()> {
    run_program_simple_no_send(text)?;
    Ok(())
}

fn main() -> anyhow::Result<()> {
    let args = Args::parse();

    //this is a separate func so it is faster to edit
    bindings::go(args)?;

    Ok(())
}
