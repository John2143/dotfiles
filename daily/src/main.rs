use std::str::FromStr;

#[derive(Debug)]
enum WindowType {
    Normal,
    Compiler,
}

impl FromStr for WindowType {
    type Err = ();
    fn from_str(s: &str) -> Result<Self, <Self as FromStr>::Err> {
        match s {
            "c" => Ok(Self::Compiler),
            "n" => Ok(Self::Normal),
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
    commands.push(tm_run(&format!("vim .")));

    commands.push(format!("tmux split-window -h"));
    commands.push(tm_run(&format!("nn")));
    commands.push(tm_run(&format!("cd ~/{name}")));
    commands.push(tm_run(&format!("clear")));

    match wtype {
        WindowType::Normal => {}
        WindowType::Compiler => {
            commands.push(format!("tmux split-window"));
            commands.push(tm_run(&format!("nn")));
            commands.push(tm_run(&format!("cd ~/{name}")));
            commands.push(tm_run(&format!("clear")));
        }
    }

    TmuxScreen { commands }
}

fn parse_single_arg(arg: &str) -> Option<TmuxScreen> {
    let x: Vec<_> = arg.split(":").collect();
    match &*x {
        [] => None,
        [name] => Some(add_window(name, name, WindowType::Normal)),
        [name, ptype] => match WindowType::from_str(ptype) {
            Ok(w) => Some(add_window(name, name, w)),
            _ => None,
        },
        [name, window_name, ptype] => match WindowType::from_str(ptype) {
            Ok(w) => Some(add_window(name, window_name, w)),
            _ => None,
        },
        [..] => None,
    }
}

fn main() {
    for arg in std::env::args().skip(1) {
        let scren = match parse_single_arg(&arg) {
            Some(s) => s,
            None => continue,
        };

        for c in scren.commands {
            println!("{c}");
        }
    }
}
