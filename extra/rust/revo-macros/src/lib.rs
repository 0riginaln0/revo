use proc_macro::TokenStream;
use quote::{ToTokens, quote};
use syn::{FnArg, ItemMod, LitStr, Visibility, parse_macro_input, spanned::Spanned};

#[proc_macro_attribute]
pub fn revo_bindings(_attr: TokenStream, item: TokenStream) -> TokenStream {
    // Concise way to return a token error on macro failure
    fn err(tokens: impl ToTokens, message: impl AsRef<str>) -> TokenStream {
        syn::Error::new_spanned(&tokens, message.as_ref())
            .to_compile_error()
            .into()
    }

    fn assert_trait(
        span: proc_macro2::Span,
        type_ident: &syn::TypePath,
        trait_ident: syn::TypePath,
    ) -> proc_macro2::TokenStream {
        quote::quote_spanned! { span =>
            const _: () = {
                const fn assert_type<T: #trait_ident>() {}
                assert_type::<#type_ident>();
            };
        }
    }

    let module = parse_macro_input!(item as ItemMod);

    // Require the macro to be attached to a module. Note that this doesn't actually create a module and exists top-level of the defining module, which also means no need to `use super::*` imports. This may change, idk if this is necessary.
    let Some((_brace, items)) = module.content else {
        return syn::Error::new_spanned(module, "#[revo_bindings] requires an inline module")
            .to_compile_error()
            .into();
    };

    //
    // Get all functions defined in this macro block.
    //
    let mut fns: Vec<proc_macro2::TokenStream> = Vec::new();
    let mut binding_sigs: Vec<(String, proc_macro2::Ident)> = Vec::new();
    let mut others: Vec<&syn::Item> = Vec::new();

    for item in items.iter() {
        match item {
            syn::Item::Fn(item_fn) => {
                // Emit a warning with private functions. We can generate either way just fine,
                // but asserting `pub` seems more expected.
                if !matches!(item_fn.vis, Visibility::Public(_)) {
                    // Span the error fo the `fn` keyword
                    return err(item_fn.sig.fn_token, "binding funtions must be `pub`");
                }
                // Ensure that the first arg exists and is not a receiver
                let maybe_vm = if let Some(vm_arg) = item_fn.sig.inputs.first() {
                    match vm_arg {
                        FnArg::Typed(pat) => match pat.ty.as_ref() {
                            syn::Type::Path(ty) => Some((pat, ty)),
                            _ => None,
                        },
                        FnArg::Receiver(receiver) => {
                            return err(receiver, "`self` is not allowed in functions");
                        }
                    }
                } else {
                    None
                };

                let vm_arg_offset = if maybe_vm.is_some() { 1 } else { 0 };

                // Ensure the type is `VM`
                let type_check = match maybe_vm {
                    Some((_ident, ty)) => {
                        // TODO: instead of a compile error, allow users to simply omit vm as the first param
                        // IDK how to do this rn
                        assert_trait(ty.span(), ty, syn::parse_quote!(::revo::VirtualMachine))
                    }
                    None => proc_macro2::TokenStream::new(),
                };

                // Next, build each fn parameter. Validate that they are of a valid type.
                // If the param type is a specific data type, also validate that the input
                // is as expected, and build the data automatically.
                let mut all_args: Vec<proc_macro2::TokenStream> = vec![];

                // Get all variables and convert from revo data into rust values
                for (i, arg) in item_fn.sig.inputs.iter().skip(vm_arg_offset).enumerate() {
                    let syn::FnArg::Typed(arg_pat) = arg else {
                        // Receivers must be first arg, which is always vm, meaning the
                        // compiler will always catch the error before our macro does
                        unreachable!();
                    };

                    let type_path = match arg_pat.ty.as_ref() {
                        syn::Type::Path(type_path) => type_path,
                        other => {
                            return err(
                                other,
                                format!("expected arg type to be `TypePath`, got `{:#?}`", other),
                            );
                        }
                    };

                    // Check that the type implements `TryFromValue`
                    let ty = arg_pat.ty.clone();
                    let pat = arg_pat.pat.clone();
                    let span = ty.span();
                    let arg_type_check =
                        assert_trait(span, type_path, syn::parse_quote!(::revo::TryFromValue));
                    all_args.push(quote!(
                        #arg_type_check
                        let #pat = <#ty as ::revo::TryFromValue>::from_value_unchecked(&internal_vm, &::revo::Value::from_raw(internal_vm.ptr, args[#i]).unwrap());
                    ));
                }

                let fn_name = item_fn.sig.ident.clone();
                let fn_params = item_fn.sig.inputs.clone();
                let fn_block = item_fn.block.clone();
                let fn_out = item_fn.sig.output.clone();
                let return_type = match &item_fn.sig.output {
                    syn::ReturnType::Default => quote!(()),
                    syn::ReturnType::Type(_, ty) => quote!(#ty),
                };
                let param_count = item_fn.sig.inputs.len() - vm_arg_offset; // don't include `vm`
                let arg_names = item_fn
                    .sig
                    .inputs
                    .iter()
                    .skip(1) // handle vm separate
                    .map(|x| match x {
                        FnArg::Receiver(_) => unreachable!(),
                        FnArg::Typed(pat) => pat.pat.clone(),
                    })
                    .collect::<Vec<_>>();

                // Get optional alternate name specified by attribute, or function name if unspecified
                let path = item_fn
                    .attrs
                    .iter()
                    .find(|x| x.meta.path().is_ident("name"))
                    .and_then(|x| x.parse_args::<LitStr>().ok())
                    .map(|x| x.value())
                    .unwrap_or_else(|| fn_name.to_string().clone());

                // Don't pass in the VM parameter when it is unspecified
                let maybe_internal_vm: proc_macro2::TokenStream = match maybe_vm {
                    Some(_) => quote!(internal_vm,),
                    None => proc_macro2::TokenStream::new(),
                };
                let expanded = quote!(
                    #type_check
                    extern "C" fn #fn_name(vm: *mut ::std::ffi::c_void, argc: usize, argv: *mut ::revo::revo_sys::RevoValue, out: *mut ::revo::revo_sys::RevoValue) -> i32 {
                        // reject if wrong number of params was provided
                        // TODO: make this work for optional params
                        if argc != #param_count {
                            return ::revo::revo_sys::REVO_ERR_ARITY as i32;
                        }

                        // Print the actual function inline so that it can be called
                        fn internal(#fn_params) #fn_out #fn_block

                        let args = unsafe { ::std::slice::from_raw_parts_mut::<::revo::revo_sys::RevoValue>(argv, argc) };

                        let vm_ptr = vm;
                        let internal_vm = ::revo::VM::from_ptr(vm_ptr);
                        #(#all_args)*
                        let return_value = internal(#maybe_internal_vm #(#arg_names),*);
                        let data = <#return_type as ::revo::TryToValue>::try_to_value(return_value);

                        // TODO: ehehehe
                        let internal_vm = ::revo::VM::from_ptr(vm_ptr);
                        match data {
                            Ok(data) => {
                                let raw_data = data.to_raw(&internal_vm).unwrap();
                                unsafe { *out = raw_data as u64; }
                                return ::revo::revo_sys::REVO_OK as i32;
                            }
                            Err(err) => {
                                unsafe { *out = 0; }
                                return ::revo::revo_sys::REVO_ERR_OTHER as i32;
                            }
                        }
                    }
                );
                fns.push(expanded);
                binding_sigs.push((path, fn_name.clone()));
            }
            other => {
                others.push(other);
            }
        }
    }

    let module_ident = module.ident;
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
            ::revo::revo_sys::RevoBinding { name: #tokens.as_ptr(),
            fn_: Some(#fn_name) }
        });
    }

    // push null binding sentinel
    bindings.push(quote! {
        ::revo::revo_sys::RevoBinding {
            name: ::std::ptr::null(),
            fn_: None,
        }
    });
    let binding_count = bindings.len();

    quote! {
        mod #module_ident {
            #(#others)*
            #(#fns)*
            #[unsafe(no_mangle)]
            pub static revo_bindings: [::revo::revo_sys::RevoBinding; #binding_count] = [
                #(#bindings),*
            ];
        }
    }
    .into()
}
