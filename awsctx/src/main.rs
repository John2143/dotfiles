use anyhow::bail;
use clap::Parser;
use nom::{
    bytes::complete::{tag, take_until},
    character::complete::space0,
    sequence::delimited,
    Finish,
};

/// Simple program change environment varables for AWS
#[derive(Parser, Debug)]
#[clap(author, version, about, long_about = None)]
struct Args {
    ///Use `gimme-aws-creds` only
    #[clap(short, long)]
    gimme_only: bool,

    /// Normally, expired credentials are hidden. Add this flag to show all your profiles from
    /// ~/.aws/credentials
    #[clap(short, long)]
    show_expired: bool,

    /// Skip fzf and select the closest match
    /// if env = `-`, then stdin will be read.
    #[clap(short, long)]
    env: Option<String>,
}

use std::{collections::HashMap, convert::Infallible, io::Read, process::Stdio, str::from_utf8};

use tokio::{io::AsyncWriteExt, process::Command};

#[derive(serde::Deserialize, Debug)]
struct Cred {
    aws_access_key_id: Option<String>,
    aws_secret_access_key: Option<String>,
    aws_session_token: Option<String>,
    aws_security_token: Option<String>,
    x_security_token_expires: Option<String>,
}

use chrono::{Duration, NaiveDateTime, ParseError, Utc};
impl Cred {
    fn parse_date_string(date_str: &str) -> Result<NaiveDateTime, ParseError> {
        let format = "%Y-%m-%dT%H:%M:%S%z";
        NaiveDateTime::parse_from_str(date_str, format)
    }

    fn is_expired(&self) -> Option<Duration> {
        self.x_security_token_expires
            .as_deref()
            .map(Self::parse_date_string)
            .map(|x| x.expect("Invalid Datestring in Credentials"))
            .map(|x| {
                let now = Utc::now().naive_utc();
                if x > now {
                    Some(x - now)
                } else {
                    None
                }
            })
            .flatten()
    }
}

fn format_duration(duration: Duration) -> String {
    let minutes = (duration.num_seconds() / 60) % 60;
    let hours = (duration.num_seconds() / 60) / 60;
    format!("{}h{}m", hours, minutes)
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
    type Err = Infallible;

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
    const CRED_LOC: &str = ".aws/credentials";
    cred_file.push(CRED_LOC);

    let f = std::fs::OpenOptions::new().read(true).open(&cred_file)?;
    let f = std::io::BufReader::new(f);

    let s: HashMap<String, Cred> = serde_ini::from_bufread(f)?;

    let profile_to_check = match cli.env {
        Some(s) if s == "-" => {
            let mut env = Default::default();
            std::io::stdin().read_to_end(&mut env)?;
            String::from_utf8(env)?
        }
        Some(env) => env,
        // If we don't supply env as a flag, launch fzf
        None => {
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

                // Show the remaining duration as a value at the start
                let fzf_line = match creds.is_expired() {
                    Some(x) => {
                        let dur = format_duration(x);
                        format!("[{dur}] {group}\n")
                    }
                    None => {
                        if cli.show_expired {
                            format!("[Expired] {group}\n")
                        } else {
                            // If don't have the -e flag, hide the expired ones.
                            continue;
                        }
                    }
                };

                cmd_stdin.write_all(fzf_line.as_bytes()).await?;
            }

            drop(cmd_stdin);

            let fzf_output = cmd.wait_with_output().await?;
            if !fzf_output.status.success() {
                return Err(anyhow::Error::msg("Failed to run fzf"));
            }

            let cmd_out = from_utf8(&fzf_output.stdout)?;
            //remove the `[expired]` from the front of the word
            let cmd_out = run_drop_tags(cmd_out)?;
            cmd_out.to_string()
        }
    };

    let profile_to_check = profile_to_check.trim();
    let profile = match s.get(profile_to_check) {
        Some(s) => s,
        None => bail!(
            "Profile {} does not exist in {}",
            profile_to_check,
            CRED_LOC
        ),
    };
    let shell: ShellOutput = std::env::var("SHELL")
        .map(|x| x.parse().unwrap())
        .unwrap_or(ShellOutput::Plain);


    shell.print_set("AWS_PROFILE", &profile_to_check);
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

fn drop_tags(input: &str) -> nom::IResult<&str, ()> {
    let (input, _) = delimited(tag("["), take_until("]"), tag("]"))(input)?;
    let (input, _) = space0(input)?;
    Ok((input, ()))
}

/// This removes brackets from a string. ex: `[asdf] 123456` -> `123456`
fn run_drop_tags(input: &str) -> anyhow::Result<&str> {
    let s = match drop_tags(input).finish() {
        Ok(s) => s.0,
        // We added the bracket on at the start, idk how this would happen
        Err(_) => panic!("Couldn't remove the brackets from the input string to fzf"),
    };

    Ok(s)
}

#[cfg(test)]
mod test {

    #[test]
    fn try_tag() {}
}
