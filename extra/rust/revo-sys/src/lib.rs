//! the rust `revo.h` wrapper
#![allow(non_upper_case_globals)]
#![allow(non_camel_case_types)]
#![allow(non_snake_case)]

include!(concat!(env!("OUT_DIR"), "/bindings.rs"));

pub const NIL: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_nil as u64);
pub const MISSING: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_missing as u64);
pub const UNDEF: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_undef as u64);
pub const NONE: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_none as u64);
pub const NO_RESULT: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_no_result as u64);
pub const NO: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_no as u64);
pub const FALSE: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_false as u64);
pub const TRUE: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_true as u64);
pub const RANGE: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_range as u64);
pub const OK: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_ok as u64);
pub const ERR: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_err as u64);
pub const SOME: RevoValue =
    REVO_BOX_TAG | ((RevoType_revo_atom as u64) << REVO_TAG_SHIFT) | (RevoAtom_ra_some as u64);
