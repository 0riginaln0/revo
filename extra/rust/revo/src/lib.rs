//! higher level interface for `revo-sys`
//! you want to work with the `VM` struct most the time

#[cfg(feature = "macros")]
extern crate revo_macros;

use std::ffi::{CStr, CString, c_void};
use std::fmt::Display;
use std::marker::PhantomData;
use std::ops::{Deref, DerefMut};
use std::rc::Rc;

#[cfg(feature = "macros")]
pub use revo_macros::*;
pub use revo_sys;
use revo_sys::*;

fn last_error_ptr(ptr: *mut ErevoVM) -> String {
    if ptr.is_null() {
        return "null vm".to_owned();
    }

    unsafe {
        let msg = erevo_vm_last_error(ptr);
        if msg.is_null() {
            return String::new();
        }
        CStr::from_ptr(msg).to_string_lossy().into_owned()
    }
}

/// sometimes you get a bare false and no message
/// revo has a little ERRNO of our own for that, right here
fn err_or_unknown(vm_ptr: *mut ErevoVM) -> String {
    let msg = last_error_ptr(vm_ptr);
    if msg.is_empty() {
        "revo call failed".to_owned()
    } else {
        msg
    }
}

fn c_void_ptr(ptr: *mut ErevoVM) -> *mut std::ffi::c_void {
    ptr as *mut std::ffi::c_void
}

fn boxed(tag: RevoType, id: u64) -> RevoValue {
    REVO_BOX_TAG | ((tag as u64) << REVO_TAG_SHIFT) | (id & REVO_PAYLOAD_MASK)
}

/// interned ids are never 0, so 0 means the call failed
fn intern_raw(vm_ptr: *mut ErevoVM, s: &str) -> Result<u64, String> {
    let id = unsafe { revo_intern(c_void_ptr(vm_ptr), s.as_ptr() as u64, s.len()) };
    if id == 0 {
        return Err(format!("failed to intern string {s:?}"));
    }
    Ok(id)
}

fn intern_atom_raw(vm_ptr: *mut ErevoVM, s: &str) -> Result<u64, String> {
    let id = unsafe { revo_intern_atom(c_void_ptr(vm_ptr), s.as_ptr() as u64, s.len()) };
    if id == 0 {
        return Err(format!("failed to intern atom {s:?}"));
    }
    Ok(id)
}

/// tied to the vm, constants are stored over there and referenced over here
#[derive(Debug)]
pub struct Program<'vm> {
    ptr: *mut ErevoProgram,
    vm_ptr: *mut ErevoVM,
    _marker: PhantomData<&'vm VM>,
}

impl Drop for Program<'_> {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe { erevo_program_destroy(self.ptr) }
        }
    }
}

impl<'vm> Program<'vm> {
    /// compile source code into a program, returns null on error
    pub fn compile(vm: &'vm VM, src: &str, name: Option<&str>) -> Result<Self, String> {
        // as_ptr() isnt nil-terminated :(
        let name_c = CString::new(name.unwrap_or("<run>"))
            .map_err(|e| format!("name contains interior nul: {e}"))?;

        let src_c = CString::new(src).map_err(|e| format!("source contains interior nul: {e}"))?;

        let ptr = unsafe { erevo_compile(vm.ptr, name_c.as_ptr(), src_c.as_ptr()) };

        if ptr.is_null() {
            return Err(vm.last_error());
        }
        Ok(Self {
            ptr,
            vm_ptr: vm.ptr,
            _marker: PhantomData,
        })
    }

    /// execute against the same vm it was compiled with
    pub fn run(&mut self) -> Result<Value, String> {
        let mut data: RevoValue = 0;

        let ok = unsafe { erevo_run(self.vm_ptr, self.ptr, &mut data) };

        if ok == 0 {
            return Err(last_error_ptr(self.vm_ptr));
        }

        Value::from_raw(self.vm_ptr, data).map_err(|e| e.to_string())
    }
}

/// a revo vm instance
///
/// explicitly `!Send + !Sync`
///
/// sorry for the field, it's zero-sized, see assertion below
#[derive(Debug)]
pub struct VM {
    pub ptr: *mut ErevoVM,
    _not_thread_safe: PhantomData<Rc<()>>,
}

pub trait VirtualMachine {}
impl VirtualMachine for VM {}

const _: () = assert!(std::mem::size_of::<VM>() == std::mem::size_of::<*mut ErevoVM>());

impl Default for VM {
    fn default() -> Self {
        Self::new()
    }
}

impl VM {
    pub fn new() -> Self {
        let ptr = unsafe { erevo_vm_create() };
        assert!(!ptr.is_null(), "erevo_vm_create returned null (oom maybe)");
        Self {
            ptr,
            _not_thread_safe: PhantomData,
        }
    }

    pub fn from_ptr(ptr: *mut c_void) -> Self {
        assert!(!ptr.is_null(), "ur ptr is null (oom maybe)");
        Self {
            ptr: ptr as *mut ErevoVM,
            _not_thread_safe: PhantomData,
        }
    }

    pub fn last_error(&self) -> String {
        last_error_ptr(self.ptr)
    }

    /// compile, run, and free a program in one step
    pub fn eval(&mut self, src: &str, name: Option<&str>) -> Result<Value, String> {
        let name_c = CString::new(name.unwrap_or("<run>"))
            .map_err(|e| format!("name contains interior nul: {e}"))?;

        let src_c = CString::new(src).map_err(|e| format!("source contains interior nul: {e}"))?;
        let mut data: RevoValue = 0;

        let ok = unsafe { erevo_eval(self.ptr, name_c.as_ptr(), src_c.as_ptr(), &mut data) };

        if ok == 0 {
            return Err(self.last_error());
        }

        Value::from_raw(self.ptr, data).map_err(|e| e.to_string())
    }

    /// read back a global; missing names come back as `:nil`
    pub fn get_global(&self, name: &str) -> Result<Value, String> {
        let raw = unsafe { revo_getglobal(c_void_ptr(self.ptr), name.as_ptr() as u64, name.len()) };
        Value::from_raw(self.ptr, raw).map_err(|e| e.to_string())
    }

    /// bind a name to a value on the vm
    pub fn set_global(&mut self, name: &str, val: &Value) -> Result<(), String> {
        let raw = val.to_raw(self)?;
        unsafe { revo_setglobal(c_void_ptr(self.ptr), name.as_ptr() as u64, name.len(), raw) };
        Ok(())
    }

    /// call a revo function value with already-converted args
    pub fn call(&mut self, func: &Value, args: &[Value]) -> Result<Value, String> {
        if !matches!(func, Value::Function(_)) {
            return Err(format!("call target is not a function: {func:?}"));
        }

        let func_raw = func.to_raw(self)?;
        let mut argv = Vec::with_capacity(args.len());
        for arg in args {
            argv.push(arg.to_raw(self)?);
        }

        let argv_ptr = if argv.is_empty() {
            std::ptr::null()
        } else {
            argv.as_ptr()
        };

        let mut out: RevoValue = 0;
        let ok = unsafe {
            revo_call(
                c_void_ptr(self.ptr),
                func_raw,
                argv.len() as u64,
                argv_ptr,
                &mut out,
            )
        };
        if ok == 0 {
            return Err(err_or_unknown(self.ptr));
        }
        Value::from_raw(self.ptr, out).map_err(|e| e.to_string())
    }
}

// TODO: Fix this
// impl Drop for VM {
//     fn drop(&mut self) {
//         if !self.ptr.is_null() {
//             unsafe { erevo_vm_destroy(self.ptr) }
//         }
//     }
// }

// i find it fucked up how i have to do all of this to make them distinct

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Atom(pub String);

impl From<String> for Atom {
    fn from(value: String) -> Self {
        Self(value)
    }
}

impl Deref for Atom {
    type Target = String;

    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl DerefMut for Atom {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0
    }
}

impl std::fmt::Display for Atom {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct TableId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct FunctionId(u64);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct OpaqueId(u64);

/// the actual revodata is f64 unless boxed
/// this one has a fat size=32 cost slapped onto it
/// and lives past vm lifetime, real data are owned by gc
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Num(f64),
    Atom(Atom),
    String(String),
    Table(TableId),
    Function(FunctionId),
    Opaque(OpaqueId),
}

impl Display for Value {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Value::Num(n) => write!(f, "{n}"),
            Value::Atom(a) => write!(f, ":{a}"),
            Value::String(s) => write!(f, "{s}"),
            Value::Table(id) => write!(f, "table#{}", id.0),
            Value::Function(id) => write!(f, "function#{}", id.0),
            Value::Opaque(id) => write!(f, "opaque#{}", id.0),
        }
    }
}

// numbers are f64, everything else is (REVO_BOX_TAG | (type << 48) | id)
const BOX_TAG: u64 = 0x7FF8000000000000;
const NAN_MASK: u64 = 0xFFF8000000000000;

// drifts with box changes
fn revo_type(d: RevoValue) -> u64 {
    if d & NAN_MASK == BOX_TAG {
        (d >> REVO_TAG_SHIFT) & u64::from(REVO_TAG_MASK)
    } else {
        RevoType_revo_number as u64
    }
}

impl Value {
    /// convert back into a raw box for passing into the vm
    /// strings and atoms are interned, so this needs the vm
    pub fn to_raw(&self, vm: &VM) -> Result<RevoValue, String> {
        self.to_raw_in(vm.ptr)
    }

    fn to_raw_in(&self, vm_ptr: *mut ErevoVM) -> Result<RevoValue, String> {
        match self {
            Value::Num(n) => Ok(n.to_bits()),
            Value::Atom(s) => Ok(boxed(RevoType_revo_atom, intern_atom_raw(vm_ptr, s)?)),
            Value::String(s) => Ok(boxed(RevoType_revo_string, intern_raw(vm_ptr, s)?)),
            Value::Table(id) => Ok(boxed(RevoType_revo_table, id.0)),
            Value::Function(id) => Ok(boxed(RevoType_revo_function, id.0)),
            Value::Opaque(id) => Ok(boxed(RevoType_revo_opaque, id.0)),
        }
    }

    /// we dont want boxes leaking into the public api
    pub fn from_raw(vm_ptr: *mut ErevoVM, val: RevoValue) -> Result<Value, &'static str> {
        match revo_type(val) {
            t if t == RevoType_revo_number as u64 => Ok(Value::Num(f64::from_bits(val))),
            t if t == RevoType_revo_atom as u64 => {
                // atoms and strings share the same string pool
                Ok(Value::Atom(Atom::from(get_revo_str(vm_ptr, val)?)))
            }
            t if t == RevoType_revo_string as u64 => Ok(Value::String(get_revo_str(vm_ptr, val)?)),
            t if t == RevoType_revo_table as u64 => {
                Ok(Value::Table(TableId(val & REVO_PAYLOAD_MASK)))
            }
            t if t == RevoType_revo_function as u64 => {
                Ok(Value::Function(FunctionId(val & REVO_PAYLOAD_MASK)))
            }
            t if t == RevoType_revo_opaque as u64 => {
                Ok(Value::Opaque(OpaqueId(val & REVO_PAYLOAD_MASK)))
            }
            _ => Err("can't deduce the type"),
        }
    }
}

/// table handle, owned by the vm and managed by its gc
#[derive(Debug)]
pub struct Table<'vm> {
    raw: RevoValue,
    vm_ptr: *mut ErevoVM,
    _marker: PhantomData<&'vm VM>,
}

impl<'vm> Table<'vm> {
    /// create an empty table
    pub fn new(vm: &'vm VM) -> Self {
        let raw = unsafe { revo_table_create(c_void_ptr(vm.ptr)) };
        Self {
            raw,
            vm_ptr: vm.ptr,
            _marker: PhantomData,
        }
    }

    /// build an array table from items
    pub fn from_items(vm: &'vm VM, items: &[Value]) -> Result<Self, String> {
        let mut raw_items = Vec::with_capacity(items.len());
        for item in items {
            raw_items.push(item.to_raw(vm)?);
        }
        let items_ptr = if raw_items.is_empty() {
            std::ptr::null()
        } else {
            raw_items.as_ptr()
        };
        let raw =
            unsafe { revo_table_from_items(c_void_ptr(vm.ptr), raw_items.len() as u64, items_ptr) };
        Ok(Self {
            raw,
            vm_ptr: vm.ptr,
            _marker: PhantomData,
        })
    }

    /// iterate over the array part of the table
    pub fn iter(&'vm self) -> TableIterator<'vm> {
        TableIterator {
            table: self,
            index: 0,
        }
    }

    fn c_ptr(&self) -> *mut std::ffi::c_void {
        c_void_ptr(self.vm_ptr)
    }

    /// number of entries; see `alen` for working the array part
    pub fn len(&self) -> u64 {
        unsafe { revo_table_len(self.c_ptr(), self.raw) }
    }

    /// array length
    pub fn alen(&self) -> u64 {
        unsafe { revo_table_alen(self.c_ptr(), self.raw) }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// missing keys come back as `None`
    pub fn get(&self, key: &Value) -> Result<Option<Value>, String> {
        let key_raw = key.to_raw_in(self.vm_ptr)?;
        let mut out: RevoValue = 0;
        let ok = unsafe { revo_table_get(self.c_ptr(), self.raw, key_raw, &mut out) };
        if ok == 0 {
            return Ok(None);
        }

        Ok(Some(
            Value::from_raw(self.vm_ptr, out).map_err(|e| e.to_string())?,
        ))
    }

    pub fn set(&mut self, key: &Value, val: &Value) -> Result<(), String> {
        let key_raw = key.to_raw_in(self.vm_ptr)?;
        let val_raw = val.to_raw_in(self.vm_ptr)?;
        let ok = unsafe { revo_table_set(self.c_ptr(), self.raw, key_raw, val_raw) };

        if ok == 0 {
            return Err(err_or_unknown(self.vm_ptr));
        }
        Ok(())
    }

    /// returns whether anything was actually removed
    pub fn remove(&mut self, key: &Value) -> Result<bool, String> {
        let key_raw = key.to_raw_in(self.vm_ptr)?;
        let ok = unsafe { revo_table_remove(self.c_ptr(), self.raw, key_raw) };

        Ok(ok != 0)
    }

    /// array indexing
    pub fn get_idx(&self, idx: u64) -> Result<Option<Value>, String> {
        let mut out: RevoValue = 0;
        let ok = unsafe { revo_table_get_idx(self.c_ptr(), self.raw, idx, &mut out) };
        if ok == 0 {
            return Ok(None);
        }
        Ok(Some(
            Value::from_raw(self.vm_ptr, out).map_err(|e| e.to_string())?,
        ))
    }

    pub fn push(&mut self, val: &Value) -> Result<(), String> {
        let val_raw = val.to_raw_in(self.vm_ptr)?;
        let ok = unsafe { revo_table_push(self.c_ptr(), self.raw, val_raw) };
        if ok == 0 {
            return Err(err_or_unknown(self.vm_ptr));
        }
        Ok(())
    }

    /// field access by name (`t.x`)
    pub fn get_name(&self, name: &str) -> Result<Option<Value>, String> {
        let mut out: RevoValue = 0;
        let ok = unsafe {
            revo_table_get_name(
                self.c_ptr(),
                self.raw,
                name.as_ptr() as u64,
                name.len(),
                &mut out,
            )
        };
        if ok == 0 {
            return Ok(None);
        }
        Ok(Some(
            Value::from_raw(self.vm_ptr, out).map_err(|e| e.to_string())?,
        ))
    }

    pub fn set_name(&mut self, name: &str, val: &Value) -> Result<(), String> {
        let val_raw = val.to_raw_in(self.vm_ptr)?;
        let ok = unsafe {
            revo_table_set_name(
                self.c_ptr(),
                self.raw,
                name.as_ptr() as u64,
                name.len(),
                val_raw,
            )
        };
        if ok == 0 {
            return Err(err_or_unknown(self.vm_ptr));
        }
        Ok(())
    }
}

pub struct TableIterator<'a> {
    table: &'a Table<'a>,
    index: usize,
}

impl<'a> Iterator for TableIterator<'a> {
    type Item = Value;

    fn next(&mut self) -> Option<Self::Item> {
        let result = self.table.get_idx(self.index as u64).ok().flatten();
        self.index += 1;
        result
    }
}

/// copies eagerly, strings randomly die of gc under vm's rule
fn get_revo_str(vm_ptr: *mut ErevoVM, val: RevoValue) -> Result<String, &'static str> {
    let id = val & REVO_PAYLOAD_MASK;
    let raw_ptr = c_void_ptr(vm_ptr);
    let len = unsafe { revo_string_length(raw_ptr, id) };
    let ptr = unsafe { revo_string_data(raw_ptr, id) };

    if ptr.is_null() {
        return Err("invalid string data");
    }

    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len) };
    Ok(String::from_utf8_lossy(bytes).into_owned())
}

#[derive(Debug)]
pub enum Error {
    ExpectedTable,
    ExpectedValueType,
    ExpectedBool,
    Other(String),
}

//
// Value conversion types
//

pub trait ToValue {
    fn to_value(self) -> Value;
}

pub trait TryToValue {
    fn try_to_value(self) -> Result<Value, Error>;
}

impl<T> ToValue for T
where
    T: TryToValue,
{
    fn to_value(self) -> Value {
        self.try_to_value().unwrap()
    }
}

pub trait TryFromValue {
    type Output;
    fn try_from_value(vm: &VM, data: &Value) -> Result<Self::Output, Error>;
    fn from_value(vm: &VM, data: &Value) -> Option<Self::Output> {
        Self::try_from_value(vm, data).ok()
    }
    fn from_value_unchecked(vm: &VM, data: &Value) -> Self::Output {
        Self::try_from_value(vm, data).unwrap()
    }
}

macro_rules! impl_num_data {
    ($($ty:ident),*) => {
        $(
            impl TryToValue for $ty {
                fn try_to_value(self) -> Result<Value, Error> {
                    Ok(Value::Num(self as f64))
                }
            }

            impl TryFromValue for $ty {
                type Output = Self;
                fn try_from_value( _vm: &VM, data: &Value) -> Result<Self::Output, Error> {
                    match data {
                        Value::Num(n) => Ok(*n as Self::Output),
                        _ => Err(Error::ExpectedValueType),
                    }
                }
            }
        )*
    };
}

impl_num_data!(
    u8, u16, u32, u64, u128, usize, i8, i16, i32, i64, i128, isize, f32, f64
);

impl TryToValue for () {
    fn try_to_value(self) -> Result<Value, Error> {
        Ok(::revo_sys::NIL.to_value())
    }
}
impl TryToValue for bool {
    fn try_to_value(self) -> Result<Value, Error> {
        Ok(match self {
            true => ::revo_sys::TRUE.to_value(),
            false => ::revo_sys::FALSE.to_value(),
        })
    }
}
impl TryFromValue for bool {
    type Output = Self;
    fn try_from_value(_vm: &VM, data: &Value) -> Result<Self::Output, Error> {
        match data {
            Value::Atom(a) => match a.as_str() {
                "true" => Ok(true),
                "false" => Ok(false),
                _ => Err(Error::ExpectedBool),
            },
            _ => Err(Error::ExpectedValueType),
        }
    }
}

impl TryToValue for String {
    fn try_to_value(self) -> Result<Value, Error> {
        Ok(Value::String(self))
    }
}
impl TryFromValue for String {
    type Output = Self;
    fn try_from_value(_vm: &VM, data: &Value) -> Result<Self::Output, Error> {
        match data {
            Value::String(s) => Ok(s.clone()),
            _ => Err(Error::ExpectedValueType),
        }
    }
}

impl TryToValue for Atom {
    fn try_to_value(self) -> Result<Value, Error> {
        Ok(Value::Atom(self))
    }
}
impl TryFromValue for Atom {
    type Output = Self;
    fn try_from_value(_vm: &VM, data: &Value) -> Result<Self::Output, Error> {
        match data {
            Value::Atom(a) => Ok(a.clone()),
            _ => Err(Error::ExpectedValueType),
        }
    }
}

impl<'a> TryToValue for Table<'a> {
    fn try_to_value(self) -> Result<Value, Error> {
        Ok(Value::Table(TableId(self.raw & REVO_PAYLOAD_MASK)))
    }
}
impl<'a> TryFromValue for Table<'a> {
    type Output = Self;
    // wrap a `Value::Table` from eval back into a handle
    fn try_from_value(vm: &VM, data: &Value) -> Result<Self::Output, Error> {
        match data {
            Value::Table(id) => Ok(Self {
                raw: boxed(RevoType_revo_table, id.0),
                vm_ptr: vm.ptr,
                _marker: PhantomData,
            }),
            _other => Err(Error::ExpectedTable),
        }
    }
}

impl<T> TryToValue for Result<T, Error>
where
    T: ToValue,
{
    fn try_to_value(self) -> Result<Value, Error> {
        self.map(ToValue::to_value)
    }
}
