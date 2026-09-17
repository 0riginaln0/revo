fn main() {
    use revo::{Data, Program, Table, VM};

    let mut vm = VM::new();

    // oneshot
    let val = vm.eval("40 + 2", None).unwrap();
    assert_eq!(val, Data::Num(42.0));
    println!("eval: {val}");

    // compile once, run as often as you like
    // > `Program` borrows the vm, so it can't outlive it
    let mut prog = Program::compile(&vm, "41 + 1", None).unwrap();
    println!("program: {}", prog.run().unwrap());
    drop(prog);

    // share state across evals through globals
    //   missing names read back as `:nil`
    vm.set_global("x", &Data::Num(21.0)).unwrap();
    println!("global: {}", vm.eval("x * 2", None).unwrap());

    // call a revo function value from rust
    let f = vm.eval("fn(a, b) a + b", None).unwrap();
    let args = [Data::Num(20.0), Data::Num(22.0)];
    println!("call: {}", vm.call(&f, &args).unwrap());

    // tables both ways
    // : build one here, hand it over, read it back
    let mut t = Table::new(&vm);
    t.set_name("answer", &Data::Num(42.0)).unwrap();

    let data = t.to_data(); // `t`'s borrow ends here, so `vm` is usable again
    vm.set_global("t", &data).unwrap();

    let back = Table::from_data(&vm, &vm.get_global("t").unwrap()).unwrap();
    println!("table: {}", back.get_name("answer").unwrap().unwrap());
}
