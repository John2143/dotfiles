use anyhow::bail;
use nom::IResult;
use regex::Regex;

#[derive(Default, Debug)]
struct Keybind {
    key: String,
    bind: String,
}

fn parse_line(input: &str, regex: &Regex) -> anyhow::Result<Keybind> {
    match regex.captures(input) {
        None => bail!("Bad capture"),
        Some(s) => {
            Ok(Keybind {
                key: s.get(1).unwrap().as_str().to_owned(),
                bind: s.get(2).unwrap().as_str().to_owned(),
            })
        }
    }
}

fn main() {
    let mut home = home::home_dir().unwrap();
    home.push(".config");
    home.push("binds.txt");
    let mut id = 100;
    let mut names = vec![];

    let regex = regex::Regex::new(r"(.+?)\s?=\s?(.+$)").unwrap();
    for line in std::fs::read_to_string(home).unwrap().lines() {
        let keybind = parse_line(line, &regex).unwrap();
        dbg!(&keybind);

        let name = format!("custom{id}");

        println!("[custom-keybindings/{name}]");
        println!("binding=['{}', '<Shift>{}']", keybind.key, keybind.key);
        println!("command='{}'", keybind.bind);
        println!("name='{id}'");

        names.push(name);

        id += 1;
    }


    println!("[/]");
    print!("custom-list=[ '__dummy__'");
    for name in &names {
        print!(", '{name}'");
    }
    println!(" ]");


    eprintln!("Added {} keybinds", names.len());
}
