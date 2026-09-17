use proc_macro::TokenStream;
use quote::{ToTokens, quote};
use syn::{FnArg, ItemMod, LitStr, Visibility, parse_macro_input};

fn type_name(ty: &syn::Type) -> Option<String> {
    if let syn::Type::Path(tp) = ty
        && let Some(seg) = tp.path.segments.last()
        && seg.arguments.is_none()
    {
        Some(seg.ident.to_string())
    } else {
        None
    }
}

const SUPPORTED_TYPES: [&str; 18] = [
    "usize", "u8", "u16", "u32", "u64", "u128", "isize", "i8", "i16", "i32", "i64", "i128", "f32",
    "f64", "bool", "String", "Table", "Data",
];

#[proc_macro_attribute]
pub fn revo_bindings(_attr: TokenStream, item: TokenStream) -> TokenStream {
    fn err(tokens: impl ToTokens, message: impl AsRef<str>) -> TokenStream {
        syn::Error::new_spanned(&tokens, message.as_ref())
            .to_compile_error()
            .into()
    }

    let module = parse_macro_input!(item as ItemMod);

    let Some((_brace, items)) = module.content else {
        return syn::Error::new_spanned(module, "#[revo_bindings] requires an inline module")
            .to_compile_error()
            .into();
    };

    let mut fns: Vec<proc_macro2::TokenStream> = Vec::new();
    let mut binding_sigs: Vec<(String, proc_macro2::Ident)> = Vec::new();

    for item in items.iter() {
        match item {
            // Iterate over every fn item defined in the bindings module
            syn::Item::Fn(item_fn) => {
                // Skip private fns
                if !matches!(item_fn.vis, Visibility::Public(_)) {
                    continue;
                }
                // Ensure that the first arg exists, and that it is of type `VM`
                let Some(FnArg::Typed(vm_arg)) = item_fn.sig.inputs.first() else {
                    return err(item_fn, "expected first argument with type `VM`");
                };
                let vm_pat = vm_arg.pat.as_ref();
                let syn::Type::Path(ty) = vm_arg.ty.as_ref() else {
                    return err(vm_arg, "expected first argument with type `VM`");
                };
                if !ty.path.is_ident("VM") {
                    return err(
                        &ty.path,
                        format!(
                            "expected `VM` as first argument, got {}",
                            ty.to_token_stream()
                        ),
                    );
                };

                // Next, build each fn parameter. Validate that they are of a valid type.
                // If the param type is a specific data type, also validate that the input
                // is as expected, and build the data automatically.
                let mut all_args: Vec<proc_macro2::TokenStream> = vec![];

                // Get all variables
                for (i, arg) in item_fn.sig.inputs.iter().skip(1).enumerate() {
                    let syn::FnArg::Typed(arg_pat) = arg else {
                        return err(arg, "expected argument");
                    };

                    let Some(name) = type_name(&arg_pat.ty) else {
                        return err(&arg_pat.ty, "expected type argument");
                    };

                    let d = quote!(let d = ::revo::Data::from_raw(vm.ptr, args[#i ]).unwrap(););
                    let pat = arg_pat.pat.clone();
                    let ty = arg_pat.ty.clone();
                    // TODO: Instead of this, make a trait that can create an arbitrary type from data
                    // then users can also just impl their own input types easily
                    all_args.push(match name.as_str() {
                        "usize" | "u8" | "u16" | "u32" | "u64" | "u128" | "isize" | "i8"
                        | "i16" | "i32" | "i64" | "i128" | "f32" | "f64" => quote!(
                            let #pat = { #d
                                let ::revo::Data::Num(n) = d else { panic!("expected num"); };
                                n as #ty
                            };
                        ),
                        "bool" => quote!(
                            let #pat = { #d
                                let ::revo::Data::Atom(n) = d else { panic!("expected :true or :false"); };
                                match n.as_str() {
                                    "true" => true,
                                    "false" => false,
                                    _ => panic!("expected :true or :false")
                                }
                            };
                        ),
                        "String" => quote!(
                            let #pat = { #d
                                let ::revo::Data::String(s) = d else { panic!("expected string"); };
                                s
                            };
                        ),
                        "Atom" => quote!(
                            let #pat = { #d
                                let ::revo::Data::Atom(a) = d else { panic!("expected string"); };
                                a
                            };
                        ),
                        "Table" => quote!(
                            let #pat = { #d
                                ::revo::Table::from_data(&#vm_pat, &d).unwrap()
                            };
                        ),
                        "Data" => quote!(
                            let #pat = { #d };
                        ),
                        _other => err(
                            pat,
                            format!(
                                "unsupported argument type `{}`, expected: {}",
                                name,
                                SUPPORTED_TYPES.join(", ")
                            ),
                        )
                        .into(),
                    });
                }

                // Set up return / out
                let ret = match &item_fn.sig.output {
                    syn::ReturnType::Default => quote!(::revo_sys::NIL),
                    syn::ReturnType::Type(_, typ) => {
                        // Assume access to `return_value` of a rust type
                        let name = type_name(typ).unwrap();
                        match name.as_str() {
                            "usize" | "u8" | "u16" | "u32" | "u64" | "u128" | "isize" | "i8"
                            | "i16" | "i32" | "i64" | "i128" | "f32" | "f64" => {
                                quote!((return_value as f64).to_bits())
                            }
                            "bool" => {
                                quote!(if return_value ::revo_sys::FALSE else ::revo_sys::TRUE)
                            }
                            "String" => {
                                quote!(Data::String(return_value).to_raw(&vm).unwrap())
                            }
                            "Atom" => {
                                quote!(Data::Atom(return_value).to_raw(&vm).unwrap())
                            }
                            "Table" => {
                                quote!(Data::Table(return_value).to_raw(&vm).unwrap())
                            }
                            "Data" => {
                                quote!(return_value.to_raw().unwrap())
                            }
                            _other => err(
                                item_fn.sig.output.clone(),
                                format!(
                                    "unsupported argument type `{}`, expected: {}",
                                    name,
                                    SUPPORTED_TYPES.join(", ")
                                ),
                            )
                            .into(),
                        }
                    }
                };

                let fn_name = item_fn.sig.ident.clone();
                let fn_block = item_fn.block.clone();
                let param_count = item_fn.sig.inputs.len() - 1; // don't include `vm`

                // get alternate name specified by attribute
                let maybe_path = item_fn
                    .attrs
                    .iter()
                    .find(|x| x.meta.path().is_ident("name"))
                    .and_then(|x| x.parse_args::<LitStr>().ok())
                    .map(|x| x.value());

                let vm_ident = &vm_arg.pat;
                let expanded = quote!(
                    extern "C" fn #fn_name(vm: *mut std::ffi::c_void, argc: usize, argv: *mut ::revo_sys::RevoData, out: *mut ::revo_sys::RevoData) {

                        // reject if wrong number of params was provided
                        // TODO: make this work for optional params
                        if argc != #param_count {
                            panic!("expected {} arguments, got {}", #param_count, argc);
                        }

                        let args = unsafe { ::std::slice::from_raw_parts_mut::<::revo_sys::RevoData>(argv, argc) };

                        let #vm_ident = ::revo::VM::from_ptr(vm);
                        #(#all_args)*
                        let return_value = #fn_block;
                        unsafe { *out = #ret; }

                    }
                );
                fns.push(expanded);
                // TODO: Allow caller to set arbitrary fn name
                binding_sigs.push((
                    maybe_path.unwrap_or_else(|| fn_name.to_string().clone()),
                    fn_name.clone(),
                ));
            }
            _other => (),
        }
    }

    let mut bindings = Vec::new();
    for (binding_name, fn_name) in binding_sigs.iter() {
        let binding_name_string = proc_macro::Literal::string(binding_name);
        let Ok(c_lit) =
            syn::parse_str::<proc_macro2::Literal>(&format!("c{}", binding_name_string))
        else {
            return err(fn_name, "unable to parse fn name");
        };

        let tokens = quote! { #c_lit };

        bindings.push(quote! {
            ::revo_sys::RevoBinding { name: #tokens.as_ptr(),
            fn_: Some(#fn_name) }
        });
    }

    // push null binding sentinel
    bindings.push(quote! {
        ::revo_sys::RevoBinding {
            name: ::std::ptr::null(),
            fn_: None,
        }
    });
    let binding_count = bindings.len();

    quote! {
        #(#fns)*
        #[unsafe(no_mangle)]
        pub static revo_bindings: [::revo_sys::RevoBinding; #binding_count] = [
            #(#bindings),*
        ];
    }
    .into()
}
