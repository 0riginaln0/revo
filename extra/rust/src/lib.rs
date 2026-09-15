#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

use std::ffi::{CStr, CString};
use std::fmt::Display;
use std::marker::PhantomData;

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

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

/// tied to the vm, constants are stored over there and referenced over here
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
    pub fn run(&mut self) -> Result<Data, String> {
        let mut data: RevoData = 0;

        let ok = unsafe { erevo_run(self.vm_ptr, self.ptr, &mut data) };

        if ok == 0 {
            return Err(last_error_ptr(self.vm_ptr));
        }

        Data::from_raw(self.vm_ptr, data).map_err(|e| e.to_string())
    }
}

pub struct VM {
    ptr: *mut ErevoVM,
}

impl Default for VM {
    fn default() -> Self {
        Self::new()
    }
}

impl VM {
    pub fn new() -> Self {
        let ptr = unsafe { erevo_vm_create() };
        assert!(!ptr.is_null(), "erevo_vm_create returned null (oom maybe)");
        Self { ptr }
    }

    pub fn last_error(&self) -> String {
        last_error_ptr(self.ptr)
    }

    /// compile, run, and free a program in one step
    pub fn eval(&mut self, src: &str, name: Option<&str>) -> Result<Data, String> {
        let name_c = CString::new(name.unwrap_or("<run>"))
            .map_err(|e| format!("name contains interior nul: {e}"))?;

        let src_c = CString::new(src).map_err(|e| format!("source contains interior nul: {e}"))?;
        let mut data: RevoData = 0;

        let ok = unsafe { erevo_eval(self.ptr, name_c.as_ptr(), src_c.as_ptr(), &mut data) };

        if ok == 0 {
            return Err(self.last_error());
        }

        Data::from_raw(self.ptr, data).map_err(|e| e.to_string())
    }
}

impl Drop for VM {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe { erevo_vm_destroy(self.ptr) }
        }
    }
}

/// the actual revodata is f64 unless boxed
/// this one has a fat size=32 cost slapped onto it
/// and lives past vm lifetime, real data are owned by gc
#[derive(Debug, Clone, PartialEq)]
pub enum Data {
    Num(f64),
    Atom(String),
    String(String),
    Table(u64),
    Function(u64),
    Foreign(u64),
}

impl Display for Data {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Data::Num(n) => write!(f, "{n}"),
            Data::Atom(a) => write!(f, ":{a}"),
            Data::String(s) => write!(f, "{s}"),
            Data::Table(id) => write!(f, "table#{id}"),
            Data::Function(id) => write!(f, "function#{id}"),
            Data::Foreign(id) => write!(f, "foreign#{id}"),
        }
    }
}

// numbers are f64, everything else is (REVO_BOX_TAG | (type << 48) | id)
const BOX_TAG: u64 = 0x7FF8000000000000;
const NAN_MASK: u64 = 0xFFF8000000000000;

// drifts with box changes
fn revo_type(d: RevoData) -> u64 {
    if d & NAN_MASK == BOX_TAG {
        (d >> REVO_TAG_SHIFT) & u64::from(REVO_TAG_MASK)
    } else {
        RevoType_revo_number as u64
    }
}

impl Data {
    /// private because we dont want boxes leaking into the public api
    fn from_raw(vm_ptr: *mut ErevoVM, val: RevoData) -> Result<Data, &'static str> {
        match revo_type(val) {
            t if t == RevoType_revo_number as u64 => Ok(Data::Num(f64::from_bits(val))),
            t if t == RevoType_revo_atom as u64 => {
                // atoms and strings share the same string pool
                Ok(Data::Atom(get_revo_str(vm_ptr, val)?))
            }
            t if t == RevoType_revo_string as u64 => Ok(Data::String(get_revo_str(vm_ptr, val)?)),
            t if t == RevoType_revo_table as u64 => {
                let id = val & REVO_PAYLOAD_MASK;
                Ok(Data::Table(id))
            }
            t if t == RevoType_revo_function as u64 => {
                let id = val & REVO_PAYLOAD_MASK;
                Ok(Data::Function(id))
            }
            t if t == RevoType_revo_foreign as u64 => {
                let id = val & REVO_PAYLOAD_MASK;
                Ok(Data::Foreign(id))
            }
            _ => Err("can't deduce the type"),
        }
    }
}

/// copies eagerly, strings randomly die of gc under vm's rule
fn get_revo_str(vm_ptr: *mut ErevoVM, val: RevoData) -> Result<String, &'static str> {
    let id = val & REVO_PAYLOAD_MASK;
    let raw_ptr = vm_ptr as *mut std::ffi::c_void;
    let len = unsafe { revo_string_length(raw_ptr, id) };
    let ptr = unsafe { revo_string_data(raw_ptr, id) };

    if ptr.is_null() {
        return Err("invalid string data");
    }

    let bytes = unsafe { std::slice::from_raw_parts(ptr as *const u8, len) };
    Ok(String::from_utf8_lossy(bytes).into_owned())
}
