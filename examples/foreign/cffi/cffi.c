// Author: Cheri Dawn (https://woem.net/)
// MIT License
// TODO: check all mallocs and maybe free() them

#include <dlfcn.h>
#include <ffi.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "revo.h"

static int load_fn(void *vm, size_t argc, RevoData *argv, RevoData *out_result) {
	if (argc != 1) return revo_c_err_arity(vm, argc, 1);
	if (!revo_is_string(argv[0])) return revo_c_err_type(vm, 0, "string", argv[0]);

	const char *sd = (const char*)revo_string_data(vm, revo_string_id(argv[0]));
	size_t sl = revo_string_length(vm, revo_string_id(argv[0]));
	char *buf = malloc(sl * sizeof(char) + 1);
	memcpy(buf, sd, sl);
	buf[sl] = 0;

	void *lib = dlopen(buf, RTLD_NOW);

	if (!lib) return revo_c_err_other(vm, "could not open lib");

	*out_result = revo_foreign_new(lib);

	return REVO_OK;
}

static int free_fn(void *vm, size_t argc, RevoData *argv, RevoData *out_result) {
	(void)vm;
	if (argc >= 1 && revo_is_foreign(argv[0])) {
		free(revo_foreign_ptr(argv[0]));
	}
	*out_result = revo_nil();
	return REVO_OK;
}

static int func_fn(void *vm, size_t argc, RevoData *argv, RevoData *out_result) {
	if (argc != 2) return revo_c_err_arity(vm, argc, 2);
	if (!revo_is_foreign(argv[0])) return revo_c_err_type(vm, 0, "foreign", argv[0]);
	if (!revo_is_string(argv[1])) return revo_c_err_type(vm, 1, "string", argv[1]);

	void *lib = revo_foreign_ptr(argv[0]);

	const char *sd = (const char*)revo_string_data(vm, revo_string_id(argv[1]));
	size_t sl = revo_string_length(vm, revo_string_id(argv[1]));
	char *buf = malloc(sl * sizeof(char) + 1);
	memcpy(buf, sd, sl);
	buf[sl] = 0;

	void *sym = dlsym(lib, buf);

	if (!sym) return revo_c_err_other(vm, "could not find sym");

	*out_result = revo_foreign_new(sym);

	return REVO_OK;
}

static int call_fn(void *vm, size_t argc, RevoData *argv, RevoData *out_result) {
	if (argc != 4) return revo_c_err_arity(vm, argc, 4);
	if (!revo_is_foreign(argv[0])) return revo_c_err_type(vm, 0, "foreign", argv[0]);
	if (!revo_is_table(argv[1])) return revo_c_err_type(vm, 1, "table", argv[1]);
	if (!revo_is_table(argv[2])) return revo_c_err_type(vm, 2, "table", argv[2]);
	if (!revo_is_string(argv[3])) return revo_c_err_type(vm, 3, "string", argv[3]);

	uint64_t nargs = revo_table_alen(vm, argv[1]);
	uint64_t nargs_typ = revo_table_alen(vm, argv[2]);
	if (nargs != nargs_typ) return revo_c_err_other(vm, "arguments and types do not match in length");

	const char *sd = (const char*)revo_string_data(vm, revo_string_id(argv[3]));
	size_t sl = revo_string_length(vm, revo_string_id(argv[3]));
	if (sl > 1) return revo_c_err_other(vm, "type string too long");
	char ret_type_s = *sd;

    ffi_type *ret_type;
	void *ret_val;

	switch (ret_type_s) {
	case 'v': ret_type = &ffi_type_void; break;
	case 'c': ret_type = &ffi_type_uint8; ret_val = malloc(sizeof(uint8_t)); break;
	case 'b': ret_type = &ffi_type_sint8; ret_val = malloc(sizeof(int8_t)); break;
	case 'C': ret_type = &ffi_type_uint16; ret_val = malloc(sizeof(uint16_t)); break;
	case 'B': ret_type = &ffi_type_sint16; ret_val = malloc(sizeof(int16_t)); break;
	case 'u': ret_type = &ffi_type_uint32; ret_val = malloc(sizeof(uint32_t)); break;
	case 'i': ret_type = &ffi_type_sint32; ret_val = malloc(sizeof(int32_t)); break;
	case 'U': ret_type = &ffi_type_uint64; ret_val = malloc(sizeof(uint64_t)); break;
	case 'I': ret_type = &ffi_type_sint64; ret_val = malloc(sizeof(int64_t)); break;
	case 'f': ret_type = &ffi_type_float; ret_val = malloc(sizeof(float)); break;
	case 'd': ret_type = &ffi_type_double; ret_val = malloc(sizeof(double)); break;
	case 'p': ret_type = &ffi_type_pointer; ret_val = malloc(sizeof(void*)); break;
	case 's': ret_type = &ffi_type_pointer; ret_val = malloc(sizeof(char*)); break;
	default: return revo_c_err_other(vm, "unsupported return type");
	}
	if (!ret_val) return revo_c_err_other(vm, "could not acquire memory for ret_val");

	void (*sym)(void) = revo_foreign_ptr(argv[0]);

	ffi_cif  call_interface;
	ffi_type **arg_types = malloc(sizeof(void*)*nargs); if (!arg_types) return revo_c_err_other(vm, "could not acquire memory for arg_types");
	void **arg_values = malloc(sizeof(void*)*nargs); if (!arg_types) return revo_c_err_other(vm, "could not acquire memory for arg_values");
	char *vbuf;

	for (uint64_t i = 0; i < nargs; i++) {
		RevoData out = {0};
		int ok = revo_table_get_idx(vm, argv[2], i, &out);
		if (!ok) return revo_c_err_other(vm, "could not get argument type");
		if (!revo_is_string(out)) return revo_c_err_other(vm, "type != string");

		const char *sd = (const char*)revo_string_data(vm, revo_string_id(out));
		size_t sl = revo_string_length(vm, revo_string_id(out));
		if (sl > 1) return revo_c_err_other(vm, "type string too long");
		char s = *sd;

		ok = revo_table_get_idx(vm, argv[1], i, &out);
		if (!ok) return revo_c_err_other(vm, "could not get argument");

		switch (s) {
		case 'v':
			arg_types[i] = &ffi_type_void;
			break;
		case 'c':
			arg_types[i] = &ffi_type_uint8;
			uint8_t *vu8 = malloc(sizeof(uint8_t));
			*vu8 = revo_num_value(out);
			arg_values[i] = vu8;
			break;
		case 'b':
			arg_types[i] = &ffi_type_sint8;
			int8_t *vi8 = malloc(sizeof(int8_t));
			*vi8 = revo_num_value(out);
			arg_values[i] = &vi8;
			break;
		case 'C':
			arg_types[i] = &ffi_type_uint16;
			uint16_t *vu16 = malloc(sizeof(uint16_t));
			*vu16 = revo_num_value(out);
			arg_values[i] = vu16;
			break;
		case 'B':
			arg_types[i] = &ffi_type_sint16;
			int16_t *vi16 = malloc(sizeof(int16_t));
			*vi16 = revo_num_value(out);
			arg_values[i] = vi16;
			break;
		case 'u':
			arg_types[i] = &ffi_type_uint32;
			uint32_t *vu32 = malloc(sizeof(uint32_t));
			*vu32 = revo_num_value(out);
			arg_values[i] = vu32;
			break;
		case 'i':
			arg_types[i] = &ffi_type_sint32;
			int32_t *vi32 = malloc(sizeof(int32_t));
			*vi32 = revo_num_value(out);
			arg_values[i] = vi32;
			break;
		case 'U':
			arg_types[i] = &ffi_type_uint64;
			uint64_t *vu64 = malloc(sizeof(uint64_t));
			*vu64 = revo_num_value(out);
			arg_values[i] = vu64;
			break;
		case 'I':
			arg_types[i] = &ffi_type_sint64;
			int64_t *vi64 = malloc(sizeof(int64_t));
			*vi64 = revo_num_value(out);
			arg_values[i] = vi64;
			break;
		case 'f':
			arg_types[i] = &ffi_type_float;
			float *vf32 = malloc(sizeof(float));
			*vf32 = revo_num_value(out);
			arg_values[i] = &vf32;
			break;
		case 'd':
			arg_types[i] = &ffi_type_double;
			double *vf64 = malloc(sizeof(double));
			*vf64 = revo_num_value(out);
			arg_values[i] = &vf64;
			break;
		case 'p':
			arg_types[i] = &ffi_type_pointer;
			void *vp = (void*)revo_foreign_ptr(out);
			arg_values[i] = vp;
			break;
		case 's':
			arg_types[i] = &ffi_type_pointer;
			const char *vsd = (const char*)revo_string_data(vm, revo_string_id(out));
			size_t vsl = revo_string_length(vm, revo_string_id(out));
			vbuf = malloc(vsl * sizeof(char) + 1); if (!vbuf) return revo_c_err_other(vm, "could not malloc for string buf");
			memcpy(vbuf, vsd, vsl);
			vbuf[vsl] = 0;
			arg_values[i] = &vbuf;
			break;
		default: return revo_c_err_other(vm, "unknown type");
		}
	}

	ffi_status st = ffi_prep_cif(&call_interface, FFI_DEFAULT_ABI, nargs, ret_type, arg_types);
    if (st != FFI_OK)
		return revo_c_err_other(vm, "could not prepare CIF");

	if (nargs == 3)
		printf("%d\n", *(int*)arg_values[0]);

	ffi_call(&call_interface, sym, ret_val, arg_values);
	for (uint64_t i = 0; i < nargs; i++) {
		switch (arg_types[i]->type) {
		case FFI_TYPE_UINT8:
		case FFI_TYPE_SINT8:
		case FFI_TYPE_UINT16:
		case FFI_TYPE_SINT16:
		case FFI_TYPE_UINT32:
		case FFI_TYPE_SINT32:
		case FFI_TYPE_UINT64:
		case FFI_TYPE_SINT64:
		case FFI_TYPE_FLOAT:
		case FFI_TYPE_DOUBLE:
			free(arg_values[i]);
			break;
		}
	}

	switch (ret_type_s) {
	case 'v':
		break;
	case 'c':
		*out_result = revo_num(*(uint8_t*)ret_val);
		break;
	case 'b':
		*out_result = revo_num(*(int8_t*)ret_val);
		break;
	case 'C':
		*out_result = revo_num(*(uint16_t*)ret_val);
		break;
	case 'B':
		*out_result = revo_num(*(int16_t*)ret_val);
		break;
	case 'u':
		*out_result = revo_num(*(uint32_t*)ret_val);
		break;
	case 'i':
		*out_result = revo_num(*(int32_t*)ret_val);
		break;
	case 'U':
		*out_result = revo_num(*(uint64_t*)ret_val);
		break;
	case 'I':
		*out_result = revo_num(*(int64_t*)ret_val);
		break;
	case 'f':
		*out_result = revo_num(*(float*)ret_val);
		break;
	case 'd':
		*out_result = revo_num(*(double*)ret_val);
		break;
	case 'p':
		*out_result = revo_foreign_new(ret_val);
		break;
	case 's':
		uint64_t sid = revo_intern(vm, (uint64_t)(uintptr_t)ret_val, strlen(ret_val));
		*out_result = revo_string(sid);
		break;
	}
	if (!ret_val) return revo_c_err_other(vm, "could not acquire memory for ret_val");

	free(arg_types);
	free(arg_values);

	return REVO_OK;
}

__attribute__((visibility("default"))) const RevoBinding revo_bindings[] = {
	{"load", load_fn},
	{"free", free_fn},
	{"func", func_fn},
	{"call", call_fn},
	{NULL, NULL},
};
