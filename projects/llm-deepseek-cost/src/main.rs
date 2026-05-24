use chrono::NaiveDate;
use clap::Parser;
use colored::Colorize;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Parser)]
#[command(name = "llm-deepseek-cost")]
#[command(about = "Day-by-day, user-by-user, model-by-model DeepSeek cost breakdown")]
struct Cli {
    /// Directory containing amount-*.csv and cost-*.csv
    #[arg(default_value = ".")]
    dir: PathBuf,

    /// Output as self-contained HTML (use "-" for stdout)
    #[arg(long, value_name = "FILE")]
    html: Option<String>,
}

#[derive(Debug, Deserialize)]
struct AmountRow {
    #[serde(rename = "utc_date")]
    utc_date: String,
    model: String,
    api_key_name: String,
    #[serde(rename = "type")]
    row_type: String,
    price: Option<f64>,
    amount: i64,
}

#[derive(Debug, Deserialize)]
struct CostRow {
    #[serde(rename = "utc_date")]
    utc_date: String,
    model: String,
    cost: f64,
}

#[derive(Debug)]
struct ModelStats {
    cost: f64,
    hit_tokens: i64,
    miss_tokens: i64,
    out_tokens: i64,
}

fn find_file(dir: &PathBuf, prefix: &str) -> Option<PathBuf> {
    let entries = fs::read_dir(dir).ok()?;
    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        if name_str.starts_with(prefix) && name_str.ends_with(".csv") {
            return Some(entry.path());
        }
    }
    None
}

fn humanize_tokens(n: i64) -> String {
    if n >= 1_000_000_000 {
        format!("{:.1}B", n as f64 / 1_000_000_000.0)
    } else if n >= 1_000_000 {
        format!("{}M", n / 1_000_000)
    } else if n >= 1_000 {
        format!("{}k", n / 1_000)
    } else if n > 0 {
        n.to_string()
    } else {
        "0".to_string()
    }
}

fn print_model_lines(models: &[(String, &ModelStats)], user_total: f64) {
    for (model, stats) in models {
        let pct = if user_total > 0.0 {
            (stats.cost / user_total) * 100.0
        } else {
            0.0
        };

        let hit = humanize_tokens(stats.hit_tokens);
        let miss = humanize_tokens(stats.miss_tokens);
        let out = humanize_tokens(stats.out_tokens);

        let mut token_parts: Vec<String> = Vec::new();
        if stats.hit_tokens > 0 {
            token_parts.push(format!("{} cache", hit));
        }
        if stats.miss_tokens > 0 {
            token_parts.push(format!("{} in", miss));
        }
        if token_parts.is_empty() {
            token_parts.push("0 in".to_string());
        }

        let token_str = format!("{} -> {} out", token_parts.join(" + "), out);

        println!(
            "     {} {} {} {}",
            format!("{:<20}", model).truecolor(128, 128, 128),
            format!("${:>7.2}", stats.cost).truecolor(128, 128, 128),
            format!("({:>5.1}%)", pct).truecolor(128, 128, 128),
            token_str.truecolor(128, 128, 128),
        );
    }
}
fn main() {
    let cli = Cli::parse();

    // --html: spawn self with CLICOLOR_FORCE=1, pipe through aha
    if let Some(html_path) = &cli.html {
        let exe = std::env::current_exe().unwrap_or_else(|_| {
            // Fallback: use argv[0] for `cargo run` compat
            std::env::args().next().map(PathBuf::from).unwrap()
        });
        let dir_arg = cli.dir.to_string_lossy().to_string();

        let output = Command::new(&exe)
            .arg(&dir_arg)
            .env("CLICOLOR_FORCE", "1")
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .output()
            .expect("Failed to spawn self for HTML generation");

        let mut aha = Command::new("aha")
            .arg("--black")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .spawn()
            .expect("aha not found on PATH — install it (nix-shell -p aha)");

        aha.stdin.take().unwrap().write_all(&output.stdout).unwrap();
        let result = aha.wait_with_output().unwrap();

        if html_path == "-" {
            std::io::stdout().write_all(&result.stdout).unwrap();
        } else {
            fs::write(html_path, &result.stdout).unwrap();
            eprintln!("Wrote {}", html_path);
        }
        return;
    }

    let amount_path = find_file(&cli.dir, "amount-")
        .unwrap_or_else(|| panic!("No amount-*.csv found in {:?}", cli.dir));
    let cost_path = find_file(&cli.dir, "cost-")
        .unwrap_or_else(|| panic!("No cost-*.csv found in {:?}", cli.dir));

    // Parse amount CSV
    let mut reader = csv::Reader::from_path(&amount_path).expect("Failed to open amount CSV");
    let mut data: HashMap<(String, String, String), ModelStats> = HashMap::new();

    for result in reader.deserialize() {
        let row: AmountRow = result.expect("Failed to parse amount row");
        let key = (row.utc_date.clone(), row.api_key_name.clone(), row.model.clone());
        let entry = data.entry(key).or_insert(ModelStats {
            cost: 0.0,
            hit_tokens: 0,
            miss_tokens: 0,
            out_tokens: 0,
        });

        if let Some(price) = row.price {
            entry.cost += price * row.amount as f64;
        }

        match row.row_type.as_str() {
            "input_cache_hit_tokens" => entry.hit_tokens += row.amount,
            "input_cache_miss_tokens" => entry.miss_tokens += row.amount,
            "output_tokens" => entry.out_tokens += row.amount,
            _ => {}
        }
    }

    // Parse cost CSV for cross-check
    let mut reader = csv::Reader::from_path(&cost_path).expect("Failed to open cost CSV");
    let mut cost_check: HashMap<(String, String), f64> = HashMap::new();

    for result in reader.deserialize() {
        let row: CostRow = result.expect("Failed to parse cost row");
        let key = (row.utc_date.clone(), row.model.clone());
        *cost_check.entry(key).or_insert(0.0) += row.cost;
    }

    // Cross-check
    let mut amount_totals: HashMap<(String, String), f64> = HashMap::new();
    for ((date, _user, model), stats) in &data {
        let key = (date.clone(), model.clone());
        *amount_totals.entry(key).or_insert(0.0) += stats.cost;
    }

    for ((date, model), cost_total) in &cost_check {
        let amount_total = amount_totals.get(&(date.clone(), model.clone())).copied().unwrap_or(0.0);
        let diff = (cost_total - amount_total).abs();
        if diff > 0.02 {
            eprintln!(
                "Warning: {} {} cost mismatch — amount CSV: ${:.4}, cost CSV: ${:.4}",
                date, model, amount_total, cost_total
            );
        }
    }

    // Group by date
    let mut dates: Vec<String> = data
        .keys()
        .map(|(d, _, _)| d.clone())
        .collect::<std::collections::BTreeSet<_>>()
        .into_iter()
        .collect();

    dates.sort_by_key(|d| NaiveDate::parse_from_str(d, "%Y-%m-%d").unwrap_or(NaiveDate::MIN));

    let mut grand_total: f64 = 0.0;

    for date in &dates {
        let parsed = NaiveDate::parse_from_str(date, "%Y-%m-%d")
            .expect("Invalid date format");
        let month_name = parsed.format("%B");
        let day = parsed.format("%d").to_string().trim_start_matches('0').to_string();

        // Compute daily totals
        let mut daily_total: f64 = 0.0;
        let mut daily_hit: i64 = 0;
        let mut daily_miss: i64 = 0;
        let mut daily_out: i64 = 0;

        for ((d, _, _), stats) in &data {
            if d == date {
                daily_total += stats.cost;
                daily_hit += stats.hit_tokens;
                daily_miss += stats.miss_tokens;
                daily_out += stats.out_tokens;
            }
        }
        grand_total += daily_total;

        // Date header
        println!(
            "{:>29}",
            format!("{} {}", month_name, day).bold().bright_cyan()
        );

        // Collect users for this date
        let mut users: Vec<(String, f64)> = data
            .iter()
            .filter(|((d, _, _), _)| d == date)
            .map(|((_, u, _), s)| (u.clone(), s.cost))
            .fold(HashMap::new(), |mut acc, (u, c)| {
                *acc.entry(u).or_insert(0.0) += c;
                acc
            })
            .into_iter()
            .collect();

        users.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

        for (user, user_total) in &users {
            if *user_total < 0.005 {
                continue;
            }
            println!(
                "{:>25} {}",
                user.white(),
                format!("${:>7.2}", user_total).yellow(),
            );

            let mut models: Vec<(String, &ModelStats)> = data
                .iter()
                .filter(|((d, u, _), _)| d == date && u == user)
                .map(|((_, _, m), s)| (m.clone(), s))
                .collect();

            models.sort_by(|a, b| b.1.cost.partial_cmp(&a.1.cost).unwrap_or(std::cmp::Ordering::Equal));

            print_model_lines(&models, *user_total);
        }

        // Daily summary row
        let daily_label = format!("Total {} {}", month_name, day);
        let mut daily_parts: Vec<String> = Vec::new();
        if daily_hit > 0 {
            daily_parts.push(format!("{} cache", humanize_tokens(daily_hit)));
        }
        if daily_miss > 0 {
            daily_parts.push(format!("{} in", humanize_tokens(daily_miss)));
        }
        if daily_parts.is_empty() {
            daily_parts.push("0 in".to_string());
        }
        let daily_token_str = format!("{} -> {} out", daily_parts.join(" + "), humanize_tokens(daily_out));

        println!(
            "{:>25} {} {} {}",
            daily_label.bold(),
            format!("${:>7.2}", daily_total).yellow().bold(),
            format!("({:>5.1}%)", 100.0).truecolor(128, 128, 128),
            daily_token_str.truecolor(128, 128, 128),
        );

        println!();
    }

    // Grand total — per-user breakdown
    let mut user_totals: HashMap<String, (f64, HashMap<String, ModelStats>)> = HashMap::new();
    for ((_date, user, model), stats) in &data {
        let entry = user_totals.entry(user.clone()).or_insert_with(|| (0.0, HashMap::new()));
        entry.0 += stats.cost;
        let model_entry = entry.1.entry(model.clone()).or_insert(ModelStats {
            cost: 0.0,
            hit_tokens: 0,
            miss_tokens: 0,
            out_tokens: 0,
        });
        model_entry.cost += stats.cost;
        model_entry.hit_tokens += stats.hit_tokens;
        model_entry.miss_tokens += stats.miss_tokens;
        model_entry.out_tokens += stats.out_tokens;
    }

    let mut user_list: Vec<(String, f64, Vec<(String, &ModelStats)>)> = user_totals
        .iter()
        .map(|(u, (total, models))| {
            let mut m: Vec<(String, &ModelStats)> = models.iter().map(|(n, s)| (n.clone(), s)).collect();
            m.sort_by(|a, b| b.1.cost.partial_cmp(&a.1.cost).unwrap_or(std::cmp::Ordering::Equal));
            (u.clone(), *total, m)
        })
        .collect();

    user_list.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap_or(std::cmp::Ordering::Equal));

    // Compute date range
    let first_date = dates.first().map(|d| {
        let p = NaiveDate::parse_from_str(d, "%Y-%m-%d").unwrap();
        format!("{} {}", p.format("%B"), p.format("%d").to_string().trim_start_matches('0'))
    }).unwrap_or_default();
    let last_date = dates.last().map(|d| {
        let p = NaiveDate::parse_from_str(d, "%Y-%m-%d").unwrap();
        format!("{} {}", p.format("%B"), p.format("%d").to_string().trim_start_matches('0'))
    }).unwrap_or_default();

    println!("{}", "---".truecolor(128, 128, 128));
    println!(
        "{:>29}",
        "Totals".bold().bright_cyan()
    );

    for (user, user_total, models) in &user_list {
        if *user_total < 0.005 {
            continue;
        }
        println!(
            "{:>25} {}",
                user.white(),
                format!("${:>7.2}", user_total).yellow(),
        );
        print_model_lines(models, *user_total);
    }

    // Underlined separator
    println!("{}", " ".repeat(70).underline());
    println!(
        "{:>25} {}   {}",
        "Grand Total".bold(),
        format!("${:>7.2}", grand_total).yellow().bold(),
        format!("{} - {}", first_date, last_date).truecolor(128, 128, 128),
    );
}
