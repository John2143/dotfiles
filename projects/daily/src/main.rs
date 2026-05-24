use std::str::FromStr;

#[derive(Debug, PartialEq, Eq)]
enum WindowType {
    Normal,
    Compiler,
    CompilerDB,
    Custom(String),
}

impl FromStr for WindowType {
    type Err = ();
    fn from_str(s: &str) -> Result<Self, <Self as FromStr>::Err> {
        match s {
            "c" => Ok(Self::Compiler),
            "n" => Ok(Self::Normal),
            "cd" => Ok(Self::CompilerDB),
            s if s.starts_with("cmd ") => Ok(Self::Custom(s.split_at(4).1.into())),
            _ => Err(()),
        }
    }
}

#[derive(Debug)]
struct TmuxScreen {
    commands: Vec<String>,
}

fn tm_run(s: &str) -> String {
    format!("tmux send '{s}' ENTER;")
}

fn add_window(name: &str, window_name: &str, wtype: WindowType) -> TmuxScreen {
    let mut commands = vec![];

    commands.push(format!("tmux new-window"));

    commands.push(format!("tmux rename-window {window_name}"));
    commands.push(tm_run(&format!("nn")));
    commands.push(tm_run(&format!("cd ~/{name}")));
    commands.push(tm_run(&format!("clear")));
    if let WindowType::Custom(cmd) = &wtype {
        commands.push(tm_run(cmd));
    }else{
        commands.push(tm_run(&format!("vim .")));

        commands.push(format!("tmux split-window -h"));
        commands.push(tm_run(&format!("nn")));
        commands.push(tm_run(&format!("cd ~/{name}")));
        commands.push(tm_run(&format!("clear")));
    }


    match wtype {
        WindowType::Normal | WindowType::Custom(_) => {}
        WindowType::Compiler => {
            commands.push(format!("tmux split-window"));
            commands.push(tm_run(&format!("nn")));
            commands.push(tm_run(&format!("cd ~/{name}")));
            commands.push(tm_run(&format!("clear")));
        }
        WindowType::CompilerDB => {
            commands.push(format!("tmux split-window"));
            commands.push(tm_run(&format!("nn")));
            commands.push(tm_run(&format!("cd ~/{name}")));
            commands.push(tm_run(&format!("clear")));

            commands.push(format!("tmux split-window"));
            commands.push(tm_run(&format!("nn")));
            commands.push(tm_run(&format!("cd ~/{name}")));
            commands.push(tm_run(&format!("clear")));
        }
    }

    TmuxScreen { commands }
}

fn parse_single_arg(arg: &str) -> Result<TmuxScreen, String> {
    let x: Vec<_> = arg.split(":").collect();
    match &*x {
        [] => Err("No name given".into()),
        [name] => Ok(add_window(name, name, WindowType::Normal)),
        [name, ptype] => match WindowType::from_str(ptype) {
            Ok(w) => Ok(add_window(name, name, w)),
            _ => Err(format!("invalid window type '{ptype}'")),
        },
        [name, window_name, ptype] => match WindowType::from_str(ptype) {
            Ok(w) => Ok(add_window(name, window_name, w)),
            _ => Err(format!("invalid window type '{ptype}'")),
        },
        [..] => Err("Too many args".into()),
    }
}

fn main() {
    for arg in std::env::args().skip(1) {
        let scren = match parse_single_arg(&arg) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("Invalid session '{arg}': {e}");
                continue;
            }
        };

        for c in scren.commands {
            println!("{c}");
        }
    }
}
