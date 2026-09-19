CC ?= cc
CFLAGS ?= -std=c99 -Wall -Wextra

INC = ../../../zig-out/include/revo
FFI_CFLAGS := $(shell pkg-config --cflags libffi 2>/dev/null)
FFI_LIBS := $(or $(shell pkg-config --libs libffi 2>/dev/null),-lffi)

ifeq ($(shell uname -s),Darwin)
SOFLAGS = -undefined dynamic_lookup
else ifeq ($(shell uname -s),Linux)
EXTRA = -ldl
endif

all: cffi.so

$(INC)/revo.h:
	cd ../../../ && zig build lib

cffi.so: cffi.c $(INC)/revo.h
	$(CC) $(CFLAGS) -fPIC -shared -I. -I$(INC) $(FFI_CFLAGS) $(SOFLAGS) $< -o $@ $(FFI_LIBS) -lm $(EXTRA)

clean:
	rm -f cffi.so

.PHONY: all clean
