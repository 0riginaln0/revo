// Author: Cheri Dawn (https://woem.net/)
// MIT License

#include <dlfcn.h>
#include <ffi.h>

#include <stdlib.h>
#include <string.h>

#include "revo.h"

// load needs func, func needs __call
static int func_fn(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res);
static int __call(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res);

// need these two otherwise we have to malloc
#define CFFI_MAX_ARGS 32

typedef union {
  uint8_t u8;
  int8_t i8;
  uint16_t u16;
  int16_t i16;
  uint32_t u32;
  int32_t i32;
  uint64_t u64;
  int64_t i64;
  float f;
  double d;
  void *p;
  char *s;
} CffiSlot;

// char -> ffi_type map
#define CFFI_TYPE_TABLE(X)                                                     \
  X('c', ffi_type_uint8)                                                       \
  X('b', ffi_type_sint8)                                                       \
  X('C', ffi_type_uint16)                                                      \
  X('B', ffi_type_sint16)                                                      \
  X('u', ffi_type_uint32)                                                      \
  X('i', ffi_type_sint32)                                                      \
  X('U', ffi_type_uint64)                                                      \
  X('I', ffi_type_sint64)                                                      \
  X('f', ffi_type_float)                                                       \
  X('d', ffi_type_double)                                                      \
  X('p', ffi_type_pointer)                                                     \
  X('s', ffi_type_pointer)                                                     \
  X('v', ffi_type_void)

static ffi_type *cffi_type_for(char c) {
#define X(ch, t)                                                               \
  case ch:                                                                     \
    return &t;
  switch (c) { CFFI_TYPE_TABLE(X) }
#undef X
  return NULL;
}

// revo number into the stack slot, point libffi at it
#define CFFI_NUM_ARG(ch, field, conv)                                          \
  case ch: {                                                                   \
    if (!revo_is_number(aout)) {                                               \
      rc = revo_c_err_other(vm, "arg must be number");                         \
      goto farewell;                                                           \
    }                                                                          \
    slots[i].field = (conv)revo_num_value(aout);                               \
    aval[i] = &slots[i].field;                                                 \
    break;                                                                     \
  }

// revo numbers are doubles
#define CFFI_NUM_RET(ch, field)                                                \
  case ch:                                                                     \
    *out_res = revo_num((double)ret_slot.field);                               \
    break;

// 1 char type atom into `out_c`
// ret: error on bad t/len
#define CFFI_CHAR_OF(vm, v, argno, out_c)                                      \
  do {                                                                         \
    if (!revo_is_atom(v))                                                      \
      return revo_c_err_type(vm, argno, "atom", v);                            \
    uint64_t _cid = revo_atom_id(v);                                           \
    if (revo_string_length(vm, _cid) != 1)                                     \
      return revo_c_err_other(vm, "type must be one char");                    \
    out_c = *(const char *)revo_string_data(vm, _cid);                         \
    if (!cffi_type_for(out_c))                                                 \
      return revo_c_err_other(vm, "unknown type");                             \
  } while (0)

// get named field from table or error
#define CFFI_FIELD(vm, tbl, name, out)                                         \
  do {                                                                         \
    if (!get_name_cstr(vm, tbl, name, out))                                    \
      return revo_c_err_other(vm, "bad callable: missing " name);              \
  } while (0)

// copy revo str val into a null-terminated mallocd cstr
// (revo_string_data is the gc owned one)
// TODO: add this to revo.h
static char *revo_to_cstr(void *vm, RevoValue v) {
  if (!revo_is_string(v))
    return NULL;

  const char *sd = (const char *)revo_string_data(vm, revo_string_id(v));
  size_t sl = revo_string_length(vm, revo_string_id(v));
  char *buf = malloc(sl + 1);
  if (!buf)
    return NULL;

  memcpy(buf, sd, sl);
  buf[sl] = 0;
  return buf;
}

// clang-format off
// (these now also exist as revo_table_set_name_cstr/get_name_cstr in revo.h)
static inline
int set_name_cstr(void *vm, RevoValue tbl, const char *name, RevoValue val) {
  return revo_table_set_name_cstr(vm, tbl, name, val);
}

static inline
int get_name_cstr(void *vm, RevoValue tbl, const char *name, RevoValue *out) {
  return revo_table_get_name_cstr(vm, tbl, name, out);
}
// clang-format on

static int do_ffi_callv(void *vm, void (*sym)(void), RevoValue *args,
                        uint64_t nargs, RevoValue sig_table, char ret_c,
                        RevoValue *out_res) {
  if (revo_table_alen(vm, sig_table) != nargs)
    return revo_c_err_other(vm, "arguments and types dont match in length");
  if (nargs > CFFI_MAX_ARGS)
    return revo_c_err_other(vm, "too many args");

  ffi_type *ret_type = cffi_type_for(ret_c);
  if (!ret_type)
    return revo_c_err_other(vm, "unsupported return type");

  ffi_type *atypes[CFFI_MAX_ARGS];
  void *aval[CFFI_MAX_ARGS];
  CffiSlot slots[CFFI_MAX_ARGS];
  char *strbufs[CFFI_MAX_ARGS] = {0};

  CffiSlot ret_slot;
  memset(&ret_slot, 0, sizeof ret_slot);
  void *ret_ptr = (ret_c == 'v') ? NULL : &ret_slot;

  int rc = REVO_OK;

  for (uint64_t i = 0; i < nargs; i++) {
    RevoValue tdata = 0;
    if (!revo_table_get_idx(vm, sig_table, i, &tdata)) {
      rc = revo_c_err_other(vm, "could not get argument type");
      goto farewell;
    }
    if (!revo_is_atom(tdata)) {
      rc = revo_c_err_other(vm, "type != atom");
      goto farewell;
    }
    uint64_t _tid = revo_atom_id(tdata);
    if (revo_string_length(vm, _tid) != 1) {
      rc = revo_c_err_other(vm, "type must be one char");
      goto farewell;
    }
    char s = *(const char *)revo_string_data(vm, _tid);
    RevoValue aout = args[i];

    atypes[i] = cffi_type_for(s);
    if (!atypes[i]) {
      rc = revo_c_err_other(vm, "unknown type");
      goto farewell;
    }

    switch (s) {
      CFFI_NUM_ARG('c', u8, uint8_t)
      CFFI_NUM_ARG('b', i8, int8_t)
      CFFI_NUM_ARG('C', u16, uint16_t)
      CFFI_NUM_ARG('B', i16, int16_t)
      CFFI_NUM_ARG('u', u32, uint32_t)
      CFFI_NUM_ARG('i', i32, int32_t)
      CFFI_NUM_ARG('U', u64, uint64_t)
      CFFI_NUM_ARG('I', i64, int64_t)
      CFFI_NUM_ARG('f', f, float)
      CFFI_NUM_ARG('d', d, double)
    case 'p': {
      if (revo_is_opaque(aout))
        slots[i].p = revo_opaque_ptr(aout);
      else if (revo_is_nil(aout))
        slots[i].p = NULL;
      else {
        rc = revo_c_err_other(vm, "pointer arg must be opaque or nil");
        goto farewell;
      }
      aval[i] = &slots[i].p;
      break;
    }
    case 's': {
      if (!revo_is_string(aout)) {
        rc = revo_c_err_other(vm, "string arg must be string");
        goto farewell;
      }
      const char *vsd =
          (const char *)revo_string_data(vm, revo_string_id(aout));

      size_t vsl = revo_string_length(vm, revo_string_id(aout));
      char *vbuf = malloc(vsl + 1);
      if (!vbuf) {
        rc = revo_c_err_other(vm, "could not malloc for string buf???");
        goto farewell;
      }

      memcpy(vbuf, vsd, vsl);
      vbuf[vsl] = 0;
      strbufs[i] = vbuf;
      slots[i].s = vbuf;
      aval[i] = &slots[i].s;
      break;
    }
    case 'v':
      rc = revo_c_err_other(vm, "void not valid as argument type");
      goto farewell;
    default:
      rc = revo_c_err_other(vm, "unknown type");
      goto farewell;
    }
  }

  {
    ffi_cif cif;
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, (unsigned int)nargs, ret_type,
                     atypes) != FFI_OK) {
      rc = revo_c_err_other(vm, "could not prepare cif");
      goto farewell;
    }
    ffi_call(&cif, sym, ret_ptr, aval);
  }

  switch (ret_c) {
  case 'v':
    *out_res = revo_nil();
    break;
    CFFI_NUM_RET('c', u8)
    CFFI_NUM_RET('b', i8)
    CFFI_NUM_RET('C', u16)
    CFFI_NUM_RET('B', i16)
    CFFI_NUM_RET('u', u32)
    CFFI_NUM_RET('i', i32)
    CFFI_NUM_RET('U', u64)
    CFFI_NUM_RET('I', i64)
    CFFI_NUM_RET('f', f)
    CFFI_NUM_RET('d', d)
  case 'p':
    *out_res = revo_opaque_new(ret_slot.p);
    break;
  case 's': {
    if (!ret_slot.s) {
      *out_res = revo_nil();
    } else {
      uint64_t sid =
          revo_intern(vm, ret_slot.s, strlen(ret_slot.s));
      *out_res = revo_string_val(sid);
    }
    break;
  }
  default:
    rc = revo_c_err_other(vm, "unsupported return type");
    goto farewell;
  }

  rc = REVO_OK;

farewell:
  for (uint64_t i = 0; i < nargs; i++)
    free(strbufs[i]);
  return rc;
}

// load(path) -> lib table { _handle = opaque, func = cfunc }
static int load_fn(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res) {
  if (argc != 1)
    return revo_c_err_arity(vm, argc, 1);
  if (!revo_is_string(argv[0]))
    return revo_c_err_type(vm, 0, "string", argv[0]);

  char *buf = revo_to_cstr(vm, argv[0]);
  if (!buf)
    return revo_c_err_other(vm, "could not read lib path");

  void *lib = dlopen(buf, RTLD_NOW);
  free(buf);

  if (!lib)
    return revo_c_err_other(vm, "could not open lib");

  RevoValue tbl = revo_table_create(vm);
  if (!revo_is_table(tbl)) {
    dlclose(lib);
    return revo_c_err_other(vm, "could not create lib table???");
  }

  if (!set_name_cstr(vm, tbl, "_handle", revo_opaque_new(lib))) {
    dlclose(lib);
    return revo_c_err_other(vm, "could not store lib handle???");
  }

  RevoValue func_c =
      revo_cfunc_new(vm, (void *)func_fn, "func", 4);
  if (!revo_is_function(func_c)) {
    dlclose(lib);
    return revo_c_err_other(vm, "could not create func binding???");
  }

  if (!set_name_cstr(vm, tbl, "func", func_c)) {
    dlclose(lib);
    return revo_c_err_other(vm, "could not store func binding???");
  }

  *out_res = tbl;
  return REVO_OK;
}

static int free_fn(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res) {
  if (argc != 1)
    return revo_c_err_arity(vm, argc, 1);
  if (!revo_is_table(argv[0]))
    return revo_c_err_type(vm, 0, "table", argv[0]);
  RevoValue h = 0;
  if (get_name_cstr(vm, argv[0], "_handle", &h) && revo_is_opaque(h)) {
    void *p = revo_opaque_ptr(h);
    if (p)
      dlclose(p);
    // dont double close
    set_name_cstr(vm, argv[0], "_handle", revo_nil());
  }
  *out_res = revo_nil();
  return REVO_OK;
}

// lib:func(name, sig, ret) -> table with __call
static int func_fn(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res) {
  if (argc != 4)
    return revo_c_err_arity(vm, argc, 4);
  if (!revo_is_table(argv[0]))
    return revo_c_err_type(vm, 0, "table", argv[0]);
  if (!revo_is_string(argv[1]))
    return revo_c_err_type(vm, 1, "string", argv[1]);
  if (!revo_is_table(argv[2]))
    return revo_c_err_type(vm, 2, "table", argv[2]);

  char ret_c;
  CFFI_CHAR_OF(vm, argv[3], 3, ret_c);
  (void)ret_c; // might be bullshit in the table but validated here

  RevoValue h = 0;
  if (!get_name_cstr(vm, argv[0], "_handle", &h) || !revo_is_opaque(h))
    return revo_c_err_type(vm, 0, "lib table", argv[0]);
  void *lib = revo_opaque_ptr(h);
  if (!lib)
    return revo_c_err_other(vm, "null lib handle???");

  char *buf = revo_to_cstr(vm, argv[1]);
  if (!buf)
    return revo_c_err_other(vm, "could not read sym name???");

  void *sym = dlsym(lib, buf);
  free(buf);

  if (!sym)
    return revo_c_err_other(vm, "could not find sym???");

  RevoValue tbl = revo_table_create(vm);
  if (!revo_is_table(tbl))
    return revo_c_err_other(vm, "could not create func table???");

  if (!set_name_cstr(vm, tbl, "_func", revo_opaque_new(sym)))
    return revo_c_err_other(vm, "could not store func ptr???");
  if (!set_name_cstr(vm, tbl, "_sig", argv[2]))
    return revo_c_err_other(vm, "could not store sig???");
  if (!set_name_cstr(vm, tbl, "_ret", argv[3]))
    return revo_c_err_other(vm, "could not store ret???");

  RevoValue call_c =
      revo_cfunc_new(vm, (void *)__call, "__call", 6);
  if (!revo_is_function(call_c))
    return revo_c_err_other(vm, "could not create __call binding???");

  if (!set_name_cstr(vm, tbl, "__call", call_c))
    return revo_c_err_other(vm, "could not store __call???");

  *out_res = tbl;
  return REVO_OK;
}

// for func tables
//
// iw(a, b, c)    # spread args (no table alloc!)
// iw{args_table} # table args
// iw()           # no args
static int __call(void *vm, size_t argc, RevoValue *argv, RevoValue *out_res) {
  if (argc < 1)
    return revo_c_err_arity(vm, argc, 1);
  if (!revo_is_table(argv[0]))
    return revo_c_err_type(vm, 0, "table", argv[0]);

  RevoValue self = argv[0];
  RevoValue fdata = 0, sig = 0, ret = 0;
  CFFI_FIELD(vm, self, "_func", &fdata);
  CFFI_FIELD(vm, self, "_sig", &sig);
  CFFI_FIELD(vm, self, "_ret", &ret);

  if (!revo_is_opaque(fdata))
    return revo_c_err_other(vm, "bad callable! _func not opaque");
  if (!revo_is_table(sig))
    return revo_c_err_other(vm, "bad callable! _sig not table");

  char ret_c;
  CFFI_CHAR_OF(vm, ret, 0, ret_c);

  void (*sym)(void) = revo_opaque_ptr(fdata);
  if (!sym)
    return revo_c_err_other(vm, "null func pointer :(");

  if (argc == 1) {
    return do_ffi_callv(vm, sym, NULL, 0, sig, ret_c, out_res);
  } else if (argc == 2 && revo_is_table(argv[1])) {
    RevoValue args_table = argv[1];
    uint64_t nargs = revo_table_alen(vm, argv[1]);
    if (nargs > CFFI_MAX_ARGS)
      return revo_c_err_other(vm, "too many args.....");

    RevoValue args[CFFI_MAX_ARGS];
    for (uint64_t i = 0; i < nargs; i++)
      if (!revo_table_get_idx(vm, args_table, i, &args[i]))
        return revo_c_err_other(vm, "could not get argument");

    return do_ffi_callv(vm, sym, args, nargs, sig, ret_c, out_res);
  } else if (argc - 1 > CFFI_MAX_ARGS) {
    return revo_c_err_other(vm, "too many args.....");
  }

  return do_ffi_callv(vm, sym, &argv[1], argc - 1, sig, ret_c, out_res);
}

const RevoBinding revo_bindings[] = {
    {"load", load_fn},
    {"free", free_fn},
    {"func", func_fn},
    {NULL, NULL},
};
