/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (C) 2021 Stephan Gerhold
 */
OUTPUT_ARCH(aarch64)

SECTIONS {
	. = 0x86400000;

	.text : { *(.text) }
	.data : { *(.data) }
}
