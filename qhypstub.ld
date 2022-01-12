/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2021 Stephan Gerhold
 */
OUTPUT_ARCH(aarch64)

SECTIONS {
	. = 0x86400000;

	/* Keep .data before exception vector table to make use of the padding */
	.text : { *(.text) }
	.rodata : { *(.rodata) }
	.data : { *(.data) }
	.text.vectab : { *(.text.vectab) }
}
