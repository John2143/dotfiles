use chrono::NaiveDate;
use clap::Parser;
use colored::Colorize;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "llm-deepseek-cost")]
#[command(about = "Day-by-day, user-by-user, model-by-model DeepSeek cost breakdown")]
struct Cli {
    /// Directory containing amount-*.csv and cost-*.csv
    #[arg(default_value = ".")]
    dir: PathBuf,
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

fn main() {
    let cli = Cli::parse();

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

        // Compute daily total
        let daily_total: f64 = data
            .iter()
            .filter(|((d, _, _), _)| d == date)
            .map(|(_, s)| s.cost)
            .sum();
        grand_total += daily_total;

        // Date header with daily total
        println!(
            "{}  {}",
            format!("{} {}", month_name, day).bold().bright_cyan(),
            format!("${:.2}", daily_total).bold().bright_cyan()
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
                " {} {} {}",
                "-".dimmed(),
                user.bold().white(),
                format!("${:.2}", user_total).bold().green()
            );

            let mut models: Vec<(String, &ModelStats)> = data
                .iter()
                .filter(|((d, u, _), _)| d == date && u == user)
                .map(|((_, _, m), s)| (m.clone(), s))
                .collect();

            models.sort_by(|a, b| b.1.cost.partial_cmp(&a.1.cost).unwrap_or(std::cmp::Ordering::Equal));

            for (model, stats) in &models {
                let pct = if *user_total > 0.0 {
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
                    "   {} {} {} {} {}",
                    "-".dimmed(),
                    format!("{:<20}", model),
                    format!("${:>7.2}", stats.cost).bright_yellow(),
                    format!("({:>5.1}%)", pct).dimmed(),
                    token_str.dimmed(),
                );
            }
        }
    }

    // Grand total
    println!("{}", "---".dimmed());
    println!(
        "{}  {}",
        "Total".bold().white(),
        format!("${:.2}", grand_total).bold().bright_green()
    );
}
