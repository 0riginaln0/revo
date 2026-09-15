use revo_sys::{Program, VM};

fn main() {
    let mut vm = VM::new();
    println!("{:?}", vm.eval("40 + 2", None).unwrap());
    println!("{:?}", vm.eval(":ok", None).unwrap());

    let mut prog = Program::compile(&vm, "41+31", None).unwrap();
    let c = prog.run().unwrap();
    println!("{c:?}");
}
