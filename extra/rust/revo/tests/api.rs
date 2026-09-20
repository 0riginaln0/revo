//! the runtime is single-threaded only (see `VM`)
//! it's a zig-side thing, the vm can only run on one thread now
//! while the harness runs `#[test]` fns on parallel threads
use revo::{Atom, Program, Table, ToValue, TryFromValue, VM, Value};

fn eval_num() {
    let mut vm = VM::new();
    assert_eq!(vm.eval("40 + 2", None).unwrap(), Value::Num(42.0));
}

fn compile_run() {
    let vm = VM::new();
    let mut prog = Program::compile(&vm, "41 + 1", None).unwrap();
    assert_eq!(prog.run().unwrap(), Value::Num(42.0));
}

fn globals_round_trip() {
    let mut vm = VM::new();
    vm.set_global("n", &Value::Num(3.5)).unwrap();
    assert_eq!(vm.get_global("n").unwrap(), Value::Num(3.5));
    vm.set_global("s", &Value::String("hello".into())).unwrap();
    assert_eq!(vm.get_global("s").unwrap(), Value::String("hello".into()));
    vm.set_global("a", &Value::Atom(Atom("ok".into()))).unwrap();
    assert_eq!(vm.get_global("a").unwrap(), Value::Atom(Atom("ok".into())));
}

fn missing_global_is_nil() {
    let vm = VM::new();
    assert_eq!(
        vm.get_global("definitely-not-set").unwrap(),
        Value::Atom(Atom("nil".into()))
    );
}

fn call_fn() {
    let mut vm = VM::new();
    let f = vm.eval("fn(x) x + 1", None).unwrap();
    assert!(matches!(f, Value::Function(_)));
    assert_eq!(vm.call(&f, &[Value::Num(41.0)]).unwrap(), Value::Num(42.0));

    let g = vm.eval("fn(a, b, c) a + b * c", None).unwrap();
    let args = [Value::Num(10.0), Value::Num(3.0), Value::Num(4.0)];
    assert_eq!(vm.call(&g, &args).unwrap(), Value::Num(22.0));

    let h = vm.eval("fn() 99", None).unwrap();
    assert_eq!(vm.call(&h, &[]).unwrap(), Value::Num(99.0));
}

fn call_non_function_errors() {
    let mut vm = VM::new();
    let err = vm.call(&Value::Num(1.0), &[]).unwrap_err();
    assert!(err.contains("not a function"), "unexpected error: {err}");
}

fn table_crud() {
    let vm = VM::new();
    let mut t = Table::new(&vm);
    assert!(t.is_empty());
    let key = Value::Atom(Atom("x".into()));
    t.set(&key, &Value::Num(99.0)).unwrap();

    assert!(!t.is_empty());
    assert_eq!(t.get(&key).unwrap(), Some(Value::Num(99.0)));
    assert_eq!(t.get(&Value::Atom(Atom("y".into()))).unwrap(), None);
    assert!(t.remove(&key).unwrap());
    assert!(!t.remove(&key).unwrap());
    assert_eq!(t.get(&key).unwrap(), None);
}

fn table_array() {
    let vm = VM::new();
    let mut t = Table::from_items(&vm, &[Value::Num(1.0), Value::Num(2.0)]).unwrap();

    assert_eq!(t.alen(), 2);
    assert_eq!(t.get_idx(0).unwrap(), Some(Value::Num(1.0)));
    assert_eq!(t.get_idx(1).unwrap(), Some(Value::Num(2.0)));
    assert_eq!(t.get_idx(2).unwrap(), None);

    t.push(&Value::Num(3.0)).unwrap();
    assert_eq!(t.alen(), 3);
    assert_eq!(t.get_idx(2).unwrap(), Some(Value::Num(3.0)));
}

fn table_names() {
    let vm = VM::new();
    let mut t = Table::new(&vm);
    t.set_name("a", &Value::Num(10.0)).unwrap();
    assert_eq!(t.get_name("a").unwrap(), Some(Value::Num(10.0)));
    assert_eq!(t.get_name("b").unwrap(), None);
}

fn table_eval_bridge() {
    let mut vm = VM::new();
    let data = vm.eval("{a = 1}", None).unwrap();
    let t = Table::from_value(&vm, &data).unwrap();

    assert_eq!(t.get_name("a").unwrap(), Some(Value::Num(1.0)));
    let back = t.to_value();
    vm.set_global("t", &back).unwrap();

    let fetched = vm.get_global("t").unwrap();
    let t2 = Table::from_value(&vm, &fetched).unwrap();
    assert_eq!(t2.get_name("a").unwrap(), Some(Value::Num(1.0)));
}

fn table_from_value_rejects_non_table() {
    let vm = VM::new();
    let err = Table::try_from_value(&vm, &Value::Num(1.0)).unwrap_err();
    std::assert_matches!(err, revo::Error::ExpectedTable);
}

#[test]
fn api() {
    eval_num();
    compile_run();
    globals_round_trip();
    missing_global_is_nil();
    call_fn();
    call_non_function_errors();
    table_crud();
    table_array();
    table_names();
    table_eval_bridge();
    table_from_value_rejects_non_table();
}
