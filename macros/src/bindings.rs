use crate::{rp, rpn, rpn_wait, CommandLineError, KeyType};

pub(crate) fn go(args: crate::Args) -> anyhow::Result<()> {
    use KeyType::*;
    match (args.key_type, &*args.key_name) {
        (Tap, "1") => rp("xdotool click --repeat 10 --delay 100 1")?,
        (Hold, "1") => rp("xdotool click --repeat 100 --delay 100 1")?,

        (Tap, "2") => rp("xdotool click --repeat 10 --delay 100 3")?,
        (Hold, "2") => rp("xdotool click --repeat 100 --delay 100 3")?,

        (Tap, "3") => rpn_wait(1000, "xdotool click --repeat 1000 --delay 200 1")?,
        (Hold, "3") => rpn("xdotool click --repeat 1000 --delay 200 3")?,

        (Tap, "4") => rpn("xset dpms force off")?,
        (Hold, "4") => rpn("echo unbound")?,

        (Tap, "5") => rpn("killall xdotool")?,
        (Hold, "5") => rpn("alacritty -e /home/john/ts/dotfiles/macros/edit.fish")?,

        (Tap, "z") => rpn("audio Schii")?,
        (Hold, "z") => rpn("audio Qude")?,

        (Tap, "x") => rpn("redshift -x")?,
        (Hold, "x") => rpn("redshift -P -O 4000")?,

        (Tap, "c") => rpn_wait(1000, "oil sort 600")?,
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
