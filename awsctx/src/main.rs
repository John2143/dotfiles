#![feature(never_type)]

use clap::Parser;

/// Simple program to greet a person
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    ///Use `gimme-aws-creds` only
    #[clap(short, long)]
    gimme_only: bool,
}

use std::{collections::HashMap, process::Stdio, str::from_utf8};

use tokio::{io::AsyncWriteExt, process::Command};

#[derive(serde::Deserialize, Debug)]
struct Cred {
    aws_access_key_id: Option<String>,
    aws_secret_access_key: Option<String>,
    aws_session_token: Option<String>,
    aws_security_token: Option<String>,
}

enum ShellOutput {
    Fish,
    Zsh,
    Bash,
    Plain,
}

impl ShellOutput {
    fn print_set(&self, var: &str, value: &str) {
        match self {
            ShellOutput::Fish => println!("set -x {var} \"{value}\""),
            ShellOutput::Zsh => println!("export {var}=\"{value}\""),
            ShellOutput::Bash => println!("export {var}=\"{value}\""),
            ShellOutput::Plain => println!("{var}=\"{value}\""),
        }
    }
}

impl std::str::FromStr for ShellOutput {
    type Err = !;

    fn from_str(s: &str) -> Result<Self, Self::Err> {
        Ok(if s.contains("fish") {
            Self::Fish
        } else if s.contains("bash") {
            Self::Bash
        } else if s.contains("zsh") {
            Self::Zsh
        } else {
            Self::Plain
        })
    }
}

async fn rm() -> anyhow::Result<()> {
    let cli = Args::parse();

    let mut cred_file = dirs::home_dir().unwrap();
    cred_file.push(".aws/credentials");

    let f = std::fs::OpenOptions::new().read(true).open(&cred_file)?;
    let f = std::io::BufReader::new(f);

    let s: HashMap<String, Cred> = serde_ini::from_bufread(f)?;

    let mut cmd = Command::new("fzf")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()?;

    let mut cmd_stdin = cmd.stdin.take().unwrap();

    for (group, creds) in s.iter() {
        if creds.aws_secret_access_key.is_none() {
            continue;
        }

        if cli.gimme_only && !group.contains("/") {
            continue;
        }

        let fzf_line = format!("{group}\n");
        cmd_stdin.write_all(fzf_line.as_bytes()).await?;
    }

    drop(cmd_stdin);

    let fzf_output = cmd.wait_with_output().await?;
    if !fzf_output.status.success() {
        return Err(anyhow::Error::msg("Failed to run fzf"));
    }

    let profile_to_check = from_utf8(&*fzf_output.stdout).unwrap().trim();

    let profile = s.get(profile_to_check).unwrap();
    let shell: ShellOutput = std::env::var("SHELL")
        .map(|x| x.parse().unwrap())
        .unwrap_or(ShellOutput::Plain);

    profile
        .aws_access_key_id
        .as_deref()
        .map(|x| shell.print_set("AWS_ACCESS_KEY_ID", x));
    profile
        .aws_secret_access_key
        .as_deref()
        .map(|x| shell.print_set("AWS_SECRET_ACCESS_KEY", x));
    profile
        .aws_session_token
        .as_deref()
        .map(|x| shell.print_set("AWS_SESSION_TOKEN", x));

    profile
        .aws_security_token
        .as_deref()
        .map(|x| println!("echo \"Security token: {x}.\""));

    Ok(())
}

#[tokio::main]
async fn main() -> Result<(), String> {
    match rm().await {
        Ok(_) => Ok(()),
        Err(e) => Err(e.to_string()),
    }
}