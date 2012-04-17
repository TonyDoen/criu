-include Makefile.inc

CFLAGS		+= -I./include
CFLAGS		+= -O0 -ggdb3

LIBS		+= -lrt -lpthread

DEFINES		+= -D_FILE_OFFSET_BITS=64
DEFINES		+= -D_GNU_SOURCE

ifneq ($(WERROR),0)
	WARNINGS += -Werror
endif

ifeq ($(DEBUG),1)
	DEFINES += -DCR_DEBUG
endif

WARNINGS	+= -Wall -Wno-unused
CFLAGS		+= $(WARNINGS) $(DEFINES)

PROGRAM		:= crtools

export CC ECHO MAKE CFLAGS LIBS ARCH DEFINES

OBJS_GEN_DEP	+= parasite-syscall.o
OBJS_GEN_DEP	+= cr-restore.o
DEPS_GEN	:= $(patsubst %.o,%.d,$(OBJS_GEN_DEP))

OBJS		+= $(OBJS_GEN_DEP)
OBJS		+= crtools.o
OBJS		+= proc_parse.o
OBJS		+= cr-dump.o
OBJS		+= cr-show.o
OBJS		+= cr-check.o
OBJS		+= util.o
OBJS		+= util-net.o
OBJS		+= sysctl.o
OBJS		+= ptrace.o
OBJS		+= kcmp-ids.o
OBJS		+= rbtree.o
OBJS		+= log.o
OBJS		+= libnetlink.o
OBJS		+= sockets.o
OBJS		+= files.o
OBJS		+= pipes.o
OBJS		+= file-ids.o
OBJS		+= namespaces.o
OBJS		+= uts_ns.o
OBJS		+= ipc_ns.o

OBJS-BLOB	+= parasite.o
SRCS-BLOB	+= $(patsubst %.o,%.c,$(OBJS-BLOB))

PIE-LDS		:= pie.lds.S

HEAD-BLOB-GEN	:= $(patsubst %.o,%-blob.h,$(OBJS-BLOB))
HEAD-BIN	:= $(patsubst %.o,%.bin,$(OBJS-BLOB))

ROBJS-BLOB	:= restorer.o
#
# Everything embedded into restorer as a separate
# object file should go here.
ROBJS		:= $(ROBJS-BLOB)
ROBJS		+= restorer-log.o

RSRCS-BLOB	+= $(patsubst %.o,%.c,$(ROBJS))

RSRCS-BLOB	+= $(patsubst %.o,%.c,$(ROBJS-BLOB))

RHEAD-BLOB-GEN	:= $(patsubst %.o,%-blob.h,$(ROBJS-BLOB))
RHEAD-BIN	:= $(patsubst %.o,%.bin,$(ROBJS-BLOB))

DEPS		:= $(patsubst %.o,%.d,$(OBJS))		\
       		   $(patsubst %.o,%.d,$(OBJS-BLOB))	\
		   $(patsubst %.o,%.d,$(ROBJS-BLOB))

GEN-OFFSETS	:= gen-offsets.sh

all: $(PROGRAM)

$(OBJS-BLOB): $(SRCS-BLOB)
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) -fpie $< -o $@

parasite-util-net.o: util-net.c
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) -fpie $< -o $@

$(HEAD-BIN): $(PIE-LDS) $(OBJS-BLOB) parasite-util-net.o
	$(E) "  GEN     " $@
	$(Q) $(LD) -T $(PIE-LDS) $(OBJS-BLOB) parasite-util-net.o -o $@

$(HEAD-BLOB-GEN): $(HEAD-BIN) $(GEN-OFFSETS)
	$(E) "  GEN     " $@
	$(Q) $(SH) $(GEN-OFFSETS) parasite > $@ || rm -f $@
	$(Q) sync

$(ROBJS): $(RSRCS-BLOB)
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) -fpie $(patsubst %.o,%.c,$@) -o $@

$(RHEAD-BIN): $(ROBJS) $(PIE-LDS)
	$(E) "  GEN     " $@
	$(Q) $(LD) -T $(PIE-LDS) $(ROBJS) -o $@

$(RHEAD-BLOB-GEN): $(RHEAD-BIN) $(GEN-OFFSETS)
	$(E) "  GEN     " $@
	$(Q) $(SH) $(GEN-OFFSETS) restorer > $@ || rm -f $@
	$(Q) sync

%.o: %.c
	$(E) "  CC      " $@
	$(Q) $(CC) -c $(CFLAGS) $< -o $@

%.i: %.c
	$(E) "  CC      " $@
	$(Q) $(CC) -E $(CFLAGS) $< -o $@

%.s: %.c
	$(E) "  CC      " $@
	$(Q) $(CC) -S $(CFLAGS) -fverbose-asm $< -o $@

$(PROGRAM): $(OBJS)
	$(E) "  LINK    " $@
	$(Q) $(CC) $(CFLAGS) $(OBJS) $(LIBS) -o $@

$(DEPS_GEN): $(HEAD-BLOB-GEN) $(RHEAD-BLOB-GEN)
%.d: %.c
	$(Q) $(CC) -M -MT $(patsubst %.d,%.o,$@) $(CFLAGS) $< -o $@

test-legacy: $(PROGRAM)
	$(Q) $(MAKE) -C test/legacy all
.PHONY: test-legacy

zdtm: $(PROGRAM)
	$(Q) $(MAKE) -C test/zdtm all
.PHONY: zdtm

test: zdtm
	$(Q) $(SH) test/zdtm.sh
.PHONY: test

rebuild:
	$(E) "  FORCE-REBUILD"
	$(Q) $(RM) -f ./*.o
	$(Q) $(RM) -f ./*.d
	$(Q) $(MAKE)
.PHONY: rebuild

clean:
	$(E) "  CLEAN"
	$(Q) $(RM) -f ./*.o
	$(Q) $(RM) -f ./*.d
	$(Q) $(RM) -f ./*.i
	$(Q) $(RM) -f ./*.img
	$(Q) $(RM) -f ./*.out
	$(Q) $(RM) -f ./*.bin
	$(Q) $(RM) -f ./$(PROGRAM)
	$(Q) $(RM) -f ./$(HEAD-BLOB-GEN)
	$(Q) $(RM) -f ./$(RHEAD-BLOB-GEN)
	$(Q) $(RM) -rf ./test/dump/
	$(Q) $(MAKE) -C test/legacy clean
	$(Q) $(MAKE) -C test/zdtm cleandep
	$(Q) $(MAKE) -C test/zdtm clean
	$(Q) $(MAKE) -C test/zdtm cleanout
	$(Q) $(MAKE) -C Documentation clean
.PHONY: clean

distclean: clean
	$(E) "  DISTCLEAN"
	$(Q) $(RM) -f ./tags
	$(Q) $(RM) -f ./cscope*
.PHONY: distclean

tags:
	$(E) "  GEN" $@
	$(Q) $(RM) -f tags
	$(Q) $(FIND) . -name '*.[hcS]' ! -path './.*' -print | xargs ctags -a
.PHONY: tags

cscope:
	$(E) "  GEN" $@
	$(Q) $(FIND) . -name '*.[hcS]' ! -path './.*' -print > cscope.files
	$(Q) $(CSCOPE) -bkqu
.PHONY: cscope

docs:
	$(Q) $(MAKE) -s -C Documentation all
.PHONY: docs

help:
	$(E) '    Targets:'
	$(E) '      all             - Build all [*] targets'
	$(E) '    * crtools         - Build crtools'
	$(E) '      zdtm            - Build zdtm test-suite'
	$(E) '      docs            - Build documentation'
	$(E) '      clean           - Clean everything'
	$(E) '      tags            - Generate tags file (ctags)'
	$(E) '      cscope          - Generate cscope database'
	$(E) '      rebuild         - Force-rebuild of [*] targets'
	$(E) '      test            - Run zdtm test-suite'
.PHONY: help

deps-targets := %.o %.s %.i $(PROGRAM) zdtm test-legacy

ifneq ($(filter $(deps-targets), $(MAKECMDGOALS)),)
	INCDEPS := 1
endif

ifeq ($(MAKECMDGOALS),)
	INCDEPS := 1
endif

ifeq ($(INCDEPS),1)
-include $(DEPS)
endif
