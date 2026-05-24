use crate::{rp, rpn, rpn_wait, CommandLineError, KeyType};

fn brightness(rest: &str) -> anyhow::Result<()>{
    rpn("redshift -x")?;
    rpn(&format!("redshift -P {rest}"))?;
    Ok(())
}

pub(crate) fn go(args: crate::Args) -> anyhow::Result<()> {
    use KeyType::*;
    match (args.key_type, &*args.key_name) {
        (Tap, "1") => rp("xdotool click --repeat 10 --delay 100 1")?,
        (Hold, "1") => rp("xdotool key --repeat 1000 --delay 100 g")?,

        (Tap, "2") => rp("xdotool click --repeat 10 --delay 100 3")?,
        (Hold, "2") => rp("xdotool click --repeat 100 --delay 100 3")?,

        (Tap, "3") => rpn_wait(1000, "xdotool click --repeat 1000 --delay 200 1")?,
        (Hold, "3") => rpn("xdotool click --repeat 1000 --delay 200 3")?,

        (Tap, "4") => rpn("xset dpms force off")?,
        (Hold, "4") => rpn("playerctl next")?,

        (Tap, "5") => rpn("killall xdotool || true ; killall little_oil || true")?,
        (Hold, "5") => rpn("alacritty -e /home/john/ts/dotfiles/macros/edit.fish")?,

        (Tap, "x") => brightness("-O 2500")?,
        (Hold, "x") => brightness("-O 2000")?,

        (Tap, "z") => brightness("")?,
        (Hold, "z") => brightness("-O 3500")?,

        (Tap, "c") => rpn_wait(1000, "oil sort 60")?,
        (Hold, "c") => rpn_wait(1000, "oil sort 600")?,

        (Tap, "space") => rp("oil empty")?,
        (Hold, "space") => rp("oil reset_inv")?,

        (kt, kn) => {
            return Err(CommandLineError::InvalidKeyCombo {
                kt,
                kn: kn.to_string(),
            }
            .into())
        }
    };

    Ok(())
}
