# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2021 Stephan Gerhold
OBJCOPY ?= objcopy

AS := $(CROSS_COMPILE)$(AS)
LD := $(CROSS_COMPILE)$(LD)
OBJCOPY := $(CROSS_COMPILE)$(OBJCOPY)

.PHONY: all
all: qhypstub.elf qhypstub.bin

qhypstub.elf: qhypstub.o qhypstub.ld
	$(LD) -n -T qhypstub.ld $(LDFLAGS) -o $@ $<

qhypstub.bin: qhypstub.elf
	$(OBJCOPY) -O binary $< $@

qhypstub-test-signed.mbn: qhypstub.elf
	qtestsign/qtestsign.py hyp -o $@ $<

# Attempt to sign by default if qtestsign was cloned in the same directory
ifneq ($(wildcard qtestsign/qtestsign.py),)
all: qhypstub-test-signed.mbn
endif

.PHONY: clean
clean:
	rm -f *.o *.elf *.bin *.mbn
