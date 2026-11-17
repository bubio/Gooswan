// Device-independent checks of the C audio adapter and interpolation state.
import std;
extern fn hostaudio_self_test() -> i64;
fn main() {
    if hostaudio_self_test() != 0 { exit(1); }
}
