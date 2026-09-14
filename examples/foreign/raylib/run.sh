zig build
cp ./zig-out/lib/libraylib_revo.dylib ./raylib.so
cp ./zig-out/lib/libraylib_revo.so ./raylib.so
revo ./one.rv
